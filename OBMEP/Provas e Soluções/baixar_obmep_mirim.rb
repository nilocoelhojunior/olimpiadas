#!/usr/bin/env ruby
# frozen_string_literal: true

# Script para baixar provas e soluções da OBMEP Mirim
# https://olimpiadamirim.obmep.org.br/provas-solucoes

require 'net/http'
require 'uri'
require 'fileutils'
require 'concurrent'

BASE_DIR = File.join(__dir__, 'downloads')
MAX_RETRIES = 3
POOL_SIZE = 5
PRINT_MUTEX = Mutex.new

# Estrutura flat: [ [nome_arquivo_final, google_drive_file_id] ]
# Nomes: obmep_mirim_ANO_fase_N_prova_N.pdf / obmep_mirim_ANO_fase_N_solucao_N.pdf
#         obmep_nivel_a_Na_prova.pdf / obmep_nivel_a_Na_solucao.pdf
DOWNLOADS = [
  # 4a Olimpiada Mirim - 2025 - 1a Fase
  ['obmep_mirim_2025_fase_1_prova_1.pdf',   '1aUUGrqoMzTvMXhZe6i_vzwquHSP7xEc5'],
  ['obmep_mirim_2025_fase_1_prova_2.pdf',   '1EuqwFpAWCRZJk0800wfZ01QRVuCjk7D9'],
  ['obmep_mirim_2025_fase_1_solucao_1.pdf', '1SlVxpAN9Ktldo0HzlgJsdsDqOnN1axZ2'],
  ['obmep_mirim_2025_fase_1_solucao_2.pdf', '1oLR44Jt7fj5nANsbHH09P1vQIgmUOI-m'],
  # 4a Olimpiada Mirim - 2025 - 2a Fase
  ['obmep_mirim_2025_fase_2_prova_1.pdf',   '1YNibd5tuJ5du77IaTo-n54NaFvYqV3uu'],
  ['obmep_mirim_2025_fase_2_prova_2.pdf',   '1Iueijq6EsIa41Nq6ocGJ_uwXi_A8rQ17'],
  ['obmep_mirim_2025_fase_2_solucao_1.pdf', '1xObbKRIDyNPOm2n91kK_zPBhZqQJXsvl'],
  ['obmep_mirim_2025_fase_2_solucao_2.pdf', '1KOl6Urwp_RBvt6HcjX0xW9jUVtvzXNyF'],
  # 3a Olimpiada Mirim - 2024 - 1a Fase
  ['obmep_mirim_2024_fase_1_prova_1.pdf',   '1wuuYb0KjGeR-y2_AwFowjWwXsxmmouf2'],
  ['obmep_mirim_2024_fase_1_prova_2.pdf',   '1ZEIBhLQ-mWY7WuGWxhBGGmlHGnjDORe_'],
  ['obmep_mirim_2024_fase_1_solucao_1.pdf', '1StMEh_bCXv2BONLY6A1guSzZtwEZZwSU'],
  ['obmep_mirim_2024_fase_1_solucao_2.pdf', '1RGAMgf2SA4PAN-rvjyKZFjj6O1Nm1lKP'],
  # 3a Olimpiada Mirim - 2024 - 2a Fase
  ['obmep_mirim_2024_fase_2_prova_1.pdf',   '1lH0hwjDi7bfMOQOtcFKIeUpRmgqt0Ely'],
  ['obmep_mirim_2024_fase_2_prova_2.pdf',   '1YNNxDdoGyq43uggVSvsfGZ7HrKlLA1xy'],
  ['obmep_mirim_2024_fase_2_solucao_1.pdf', '1TK89XwnKTTv6LGJWqT-RSUygsOEmlIFy'],
  ['obmep_mirim_2024_fase_2_solucao_2.pdf', '1dXudiWQMvNz81fRB6kFLBKTF7nOmuvFH'],
  # 2a Olimpiada Mirim - 2023 - 1a Fase
  ['obmep_mirim_2023_fase_1_prova_1.pdf',   '1qOExhUNEc42sfNFo5_8CwZsDrkh6SWrg'],
  ['obmep_mirim_2023_fase_1_prova_2.pdf',   '1X-y9ery4DhthT7vziMCtKq1E39oz0gFo'],
  ['obmep_mirim_2023_fase_1_solucao_1.pdf', '1LlYxRwl3FGx35nqwIawYOVzTbXiizs8I'],
  ['obmep_mirim_2023_fase_1_solucao_2.pdf', '1WQDbufgEPRy6OuCLO4wqedVJg6SlLYph'],
  # 2a Olimpiada Mirim - 2023 - 2a Fase
  ['obmep_mirim_2023_fase_2_prova_1.pdf',   '1DggNOWqHJ7Pzjz3Bv8k5xkO19Si468Zz'],
  ['obmep_mirim_2023_fase_2_prova_2.pdf',   '1wSTt0DjtLDKVMDfHygu_RyarZL0kVpcB'],
  ['obmep_mirim_2023_fase_2_solucao_1.pdf', '1EdHr2VFeJp7rhk5COkWdyc6sqQiGQvqp'],
  ['obmep_mirim_2023_fase_2_solucao_2.pdf', '1m6nm69b7Up0D-VXVgdt9wd5YOAxXKpOY'],
  # 1a Olimpiada Mirim - 2022 - 1a Fase
  ['obmep_mirim_2022_fase_1_prova_1.pdf',   '1ODPUse4q4GQ3WsFeiS7P2jNqtRraWpuT'],
  ['obmep_mirim_2022_fase_1_prova_2.pdf',   '1PfJNAM91orv-XsSuc6GzOtQY93i2356X'],
  ['obmep_mirim_2022_fase_1_solucao_1.pdf', '1Xs_Iz0hwecGcbczKKBX0x0Rrt1x4D1IR'],
  ['obmep_mirim_2022_fase_1_solucao_2.pdf', '1bTuH2iudsF9mLKh8e0o-fUaMg-rFIgOa'],
  # 1a Olimpiada Mirim - 2022 - 2a Fase
  ['obmep_mirim_2022_fase_2_prova_1.pdf',   '1n48zPM8O-0jq_vsyi-r_uWC6H6Rv13tF'],
  ['obmep_mirim_2022_fase_2_prova_2.pdf',   '1-iBjSrp_U5EoepgzgjX_h7fxtnwAb0_R'],
  ['obmep_mirim_2022_fase_2_solucao_1.pdf', '105W-GcQFXJgsmnDFX7Ku5Wxw0mLQBIwd'],
  ['obmep_mirim_2022_fase_2_solucao_2.pdf', '1w6wNNbHIPjkbCKSeYhiVKl4rDB4xb6Zz'],
  # OBMEP - Nivel A (2019-2021) - Provas
  ['obmep_nivel_a_1a_prova.pdf', '1Clj_jeVBzSShbxrWTHB8DxDvegwKWtBx'],
  ['obmep_nivel_a_2a_prova.pdf', '1gj5_LQ-_4CH9PfT66sQhtwPsbVjmwmXi'],
  ['obmep_nivel_a_3a_prova.pdf', '1GmV6Al8jEZPWpavh8vtztY5CI5caL3fz'],
  # OBMEP - Nivel A (2019-2021) - Solucoes
  ['obmep_nivel_a_1a_solucao.pdf', '198bKB4oZ8atJ4DoPDtY9TCZ3poecAyG1'],
  ['obmep_nivel_a_2a_solucao.pdf', '1636hs3K9m5kjz2ExCXzsMjZ9REgxhTSS'],
  ['obmep_nivel_a_3a_solucao.pdf', '1_Q6FqdOzKVx0tYicM8BTjnpK7k2CqkUK'],
]

def baixar_google_drive(file_id, destino)
  # URL de download direto do Google Drive
  url = "https://drive.google.com/uc?export=download&id=#{file_id}"
  max_redirects = 5
  tentativa = 0

  loop do
    tentativa += 1
    if tentativa > max_redirects
      puts "  ERRO: Muitos redirecionamentos para #{File.basename(destino)}"
      return false
    end

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 60

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    case response
    when Net::HTTPRedirection
      url = response['location']
    when Net::HTTPSuccess
      # Verificar se é página de confirmação (arquivo grande)
      if response.body.include?('download_warning') || response.body.include?('confirm=')
        # Extrair link de confirmação
        if (match = response.body.match(/confirm=([0-9A-Za-z_-]+)/))
          url = "https://drive.google.com/uc?export=download&confirm=#{match[1]}&id=#{file_id}"
          next
        end
      end

      # Verificar se é HTML (página de erro ou confirmação)
      content_type = response['content-type'] || ''
      if content_type.include?('text/html') && !content_type.include?('pdf')
        # Tentar URL alternativa
        if tentativa == 1
          url = "https://drive.google.com/uc?export=download&confirm=t&id=#{file_id}"
          next
        end
        puts "  AVISO: Resposta HTML inesperada para #{File.basename(destino)}"
      end

      File.open(destino, 'wb') { |f| f.write(response.body) }
      return true
    else
      puts "  ERRO: HTTP #{response.code} ao baixar #{File.basename(destino)}"
      return false
    end
  end
end

FileUtils.mkdir_p(BASE_DIR)

pool = Concurrent::FixedThreadPool.new(POOL_SIZE)
total = Concurrent::AtomicFixnum.new(0)
sucesso = Concurrent::AtomicFixnum.new(0)
falha = Concurrent::AtomicFixnum.new(0)

puts "\n📚 Baixando #{DOWNLOADS.size} arquivos para #{BASE_DIR}\n"

futures = DOWNLOADS.map do |nome, file_id|
  Concurrent::Future.execute(executor: pool) do
    total.increment
    destino = File.join(BASE_DIR, nome)

    if File.exist?(destino) && File.size(destino) > 1024
      PRINT_MUTEX.synchronize { puts "  ✅ Já existe: #{nome}" }
      sucesso.increment
      next
    end

    downloaded = false
    MAX_RETRIES.times do |attempt|
      begin
        PRINT_MUTEX.synchronize { print "  ⬇️  Baixando: #{nome} (tentativa #{attempt + 1})..." }
        if baixar_google_drive(file_id, destino)
          tamanho = File.size(destino)
          PRINT_MUTEX.synchronize { puts " OK (#{(tamanho / 1024.0).round(1)} KB)" }
          sucesso.increment
          downloaded = true
          break
        else
          raise "download retornou false"
        end
      rescue StandardError => e
        if attempt < MAX_RETRIES - 1
          PRINT_MUTEX.synchronize { puts " falhou (#{e.message}), retentando..." }
          sleep(1 * (attempt + 1))
        else
          PRINT_MUTEX.synchronize { puts " ERRO após #{MAX_RETRIES} tentativas: #{e.message}" }
          falha.increment
        end
      end
    end
  end
end

futures.each(&:wait)

pool.shutdown
pool.wait_for_termination

puts "\n#{'=' * 60}"
puts "Resumo: #{sucesso.value}/#{total.value} baixados com sucesso, #{falha.value} falha(s)"
puts "Arquivos salvos em: #{BASE_DIR}"
puts '=' * 60
