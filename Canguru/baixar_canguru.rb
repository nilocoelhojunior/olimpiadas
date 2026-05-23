#!/usr/bin/env ruby
# frozen_string_literal: true

# Script para baixar provas e gabaritos do Concurso Canguru de Matematica
# https://www.cangurudematematicabrasil.com.br/provas-anteriores

require 'net/http'
require 'uri'
require 'fileutils'
require 'concurrent'

BASE_DIR = File.join(__dir__, 'downloads')
MAX_RETRIES = 3
POOL_SIZE = 5
PRINT_MUTEX = Mutex.new

NIVEL_CODES = {
  'Nivel P (Pre-Ecolier)' => 'p',
  'Nivel E (Ecolier)'     => 'e',
  'Nivel B (Benjamin)'    => 'b',
  'Nivel C (Cadet)'       => 'c',
  'Nivel J (Junior)'      => 'j',
  'Nivel S (Student)'     => 's',
}.freeze

# Estrutura: { "Ano" => { "Nivel" => { portugues: url, ingles: url, gabarito: url } } }
DOWNLOADS = {
  '2025' => {
    'Nivel P (Pre-Ecolier)' => {
      portugues: 'https://alunoprovas.s3.us-east-1.amazonaws.com/arquivosescola/prova/2025/PDFs/01_Nivel_P_CANGURU2025_PROVA_PORT.pdf',
      ingles:    'https://alunoprovas.s3.us-east-1.amazonaws.com/arquivosescola/prova/2025/PDFs/01_Nivel_P_CANGURU2025_PROVA_ING.pdf',
      gabarito:  'https://upmat-gestao.s3.us-west-2.amazonaws.com/Concurso+Canguru/Gabaritos/2025/GABARITO_CANGURU_2025-1.pdf',
    },
    'Nivel E (Ecolier)' => {
      portugues: 'https://alunoprovas.s3.us-east-1.amazonaws.com/arquivosescola/prova/2025/PDFs/02_Nivel_E_CANGURU2025_PROVA_PORT.pdf',
      ingles:    'https://alunoprovas.s3.us-east-1.amazonaws.com/arquivosescola/prova/2025/PDFs/02_Nivel_E_CANGURU2025_PROVA_ING.pdf',
      gabarito:  'https://upmat-gestao.s3.us-west-2.amazonaws.com/Concurso+Canguru/Gabaritos/2025/GABARITO_CANGURU_2025-2.pdf',
    },
    'Nivel B (Benjamin)' => {
      portugues: 'https://alunoprovas.s3.us-east-1.amazonaws.com/arquivosescola/prova/2025/PDFs/03_Nivel_B_CANGURU2025_PROVA_PORT.pdf',
      ingles:    'https://alunoprovas.s3.us-east-1.amazonaws.com/arquivosescola/prova/2025/PDFs/03_Nivel_B_CANGURU2025_PROVA_ING.pdf',
      gabarito:  'https://upmat-gestao.s3.us-west-2.amazonaws.com/Concurso+Canguru/Gabaritos/2025/GABARITO_CANGURU_2025-3.pdf',
    },
    'Nivel C (Cadet)' => {
      portugues: 'https://alunoprovas.s3.us-east-1.amazonaws.com/arquivosescola/prova/2025/PDFs/04_Nivel_C_CANGURU2025_PROVA_PORT.pdf',
      ingles:    'https://alunoprovas.s3.us-east-1.amazonaws.com/arquivosescola/prova/2025/PDFs/04_Nivel_C_CANGURU2025_PROVA_ING.pdf',
      gabarito:  'https://upmat-gestao.s3.us-west-2.amazonaws.com/Concurso+Canguru/Gabaritos/2025/GABARITO_CANGURU_2025-4.pdf',
    },
    'Nivel J (Junior)' => {
      portugues: 'https://alunoprovas.s3.us-east-1.amazonaws.com/arquivosescola/prova/2025/PDFs/05_Nivel_J_CANGURU2025_PROVA_PORT.pdf',
      ingles:    'https://alunoprovas.s3.us-east-1.amazonaws.com/arquivosescola/prova/2025/PDFs/05_Nivel_J_CANGURU2025_PROVA_ING.pdf',
      gabarito:  'https://upmat-gestao.s3.us-west-2.amazonaws.com/Concurso+Canguru/Gabaritos/2025/GABARITO_CANGURU_2025-5.pdf',
    },
    'Nivel S (Student)' => {
      portugues: 'https://alunoprovas.s3.us-east-1.amazonaws.com/arquivosescola/prova/2025/PDFs/06_Nivel_S_CANGURU2025_PROVA_PORT.pdf',
      ingles:    'https://alunoprovas.s3.us-east-1.amazonaws.com/arquivosescola/prova/2025/PDFs/06_Nivel_S_CANGURU2025_PROVA_ING.pdf',
      gabarito:  'https://upmat-gestao.s3.us-west-2.amazonaws.com/Concurso+Canguru/Gabaritos/2025/GABARITO_CANGURU_2025-6.pdf',
    },
  },
  '2024' => {
    'Nivel P (Pre-Ecolier)' => {
      portugues: 'https://alunoprovas.s3.amazonaws.com/arquivosescola/prova/2024/PDFs/ProvaP_PT.pdf',
      ingles:    'https://alunoprovas.s3.amazonaws.com/arquivosescola/prova/2024/PDFs/ProvaP_EN.pdf',
      gabarito:  'https://upmat-gestao.s3.us-west-2.amazonaws.com/Concurso+Canguru/Gabaritos/2024/GABARITO_CANGURU_2024-1.pdf',
    },
    'Nivel E (Ecolier)' => {
      portugues: 'https://alunoprovas.s3.amazonaws.com/arquivosescola/prova/2024/PDFs/ProvaE_PT.pdf',
      ingles:    'https://alunoprovas.s3.amazonaws.com/arquivosescola/prova/2024/PDFs/ProvaE_EN.pdf',
      gabarito:  'https://upmat-gestao.s3.us-west-2.amazonaws.com/Concurso+Canguru/Gabaritos/2024/GABARITO_CANGURU_2024-2.pdf',
    },
    'Nivel B (Benjamin)' => {
      portugues: 'https://alunoprovas.s3.amazonaws.com/arquivosescola/prova/2024/PDFs/ProvaB_PT.pdf',
      ingles:    'https://alunoprovas.s3.amazonaws.com/arquivosescola/prova/2024/PDFs/ProvaB_EN.pdf',
      gabarito:  'https://upmat-gestao.s3.us-west-2.amazonaws.com/Concurso+Canguru/Gabaritos/2024/GABARITO_CANGURU_2024-3.pdf',
    },
    'Nivel C (Cadet)' => {
      portugues: 'https://alunoprovas.s3.amazonaws.com/arquivosescola/prova/2024/PDFs/ProvaC_PT.pdf',
      ingles:    'https://alunoprovas.s3.amazonaws.com/arquivosescola/prova/2024/PDFs/ProvaC_EN.pdf',
      gabarito:  'https://upmat-gestao.s3.us-west-2.amazonaws.com/Concurso+Canguru/Gabaritos/2024/GABARITO_CANGURU_2024-4.pdf',
    },
    'Nivel J (Junior)' => {
      portugues: 'https://alunoprovas.s3.amazonaws.com/arquivosescola/prova/2024/PDFs/ProvaJ_PT.pdf',
      ingles:    'https://alunoprovas.s3.amazonaws.com/arquivosescola/prova/2024/PDFs/ProvaJ_EN.pdf',
      gabarito:  'https://upmat-gestao.s3.us-west-2.amazonaws.com/Concurso+Canguru/Gabaritos/2024/GABARITO_CANGURU_2024-5.pdf',
    },
    'Nivel S (Student)' => {
      portugues: 'https://alunoprovas.s3.amazonaws.com/arquivosescola/prova/2024/PDFs/ProvaS_PT.pdf',
      ingles:    'https://alunoprovas.s3.amazonaws.com/arquivosescola/prova/2024/PDFs/ProvaS_EN.pdf',
      gabarito:  'https://upmat-gestao.s3.us-west-2.amazonaws.com/Concurso+Canguru/Gabaritos/2024/GABARITO_CANGURU_2024-6.pdf',
    },
  },
  '2023' => {
    'Nivel P (Pre-Ecolier)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2023/Prova+N%C3%ADvel+P+2023.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2023/PreEcolier+ingl%C3%AAs+2023.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2023/Gabarito+N%C3%ADvel+P+2023.pdf',
    },
    'Nivel E (Ecolier)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2023/Prova+N%C3%ADvel+E+2023.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2023/Ecolier+ingl%C3%AAs+2023.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2023/Gabarito+N%C3%ADvel+E+2023.pdf',
    },
    'Nivel B (Benjamin)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2023/Prova+N%C3%ADvel+B+2023.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2023/Benjamin+ingl%C3%AAs+2023.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2023/Gabarito+N%C3%ADvel+B+2023.pdf',
    },
    'Nivel C (Cadet)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2023/Prova+N%C3%ADvel+C+2023.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2023/Cadet+ingl%C3%AAs+2023.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2023/Gabarito+N%C3%ADvel+C+2023.pdf',
    },
    'Nivel J (Junior)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2023/Prova+N%C3%ADvel+J+2023.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2023/Junior+ingl%C3%AAs+2023.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2023/Gabarito+N%C3%ADvel+J+2023.pdf',
    },
    'Nivel S (Student)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2023/Prova+N%C3%ADvel+S+2023.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2023/Student+ingl%C3%AAs+2023.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2023/Gabarito+N%C3%ADvel+S+2023.pdf',
    },
  },
  '2022' => {
    'Nivel P (Pre-Ecolier)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2022/Prova+N%C3%ADvel+P+2022.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2022/PreEcolier+ingl%C3%AAs+2022.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2022/Gabarito+N%C3%ADvel+P+2022.pdf',
    },
    'Nivel E (Ecolier)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2022/Prova+N%C3%ADvel+E+2022.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2022/Ecolier+ingl%C3%AAs+2022.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2022/Gabarito+N%C3%ADvel+E+2022.pdf',
    },
    'Nivel B (Benjamin)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2022/Prova+N%C3%ADvel+B+2022.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2022/Benjamin+ingl%C3%AAs+2022.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2022/Gabarito+N%C3%ADvel+B+2022.pdf',
    },
    'Nivel C (Cadet)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2022/Prova+N%C3%ADvel+C+2022.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2022/Cadet+ingl%C3%AAs+2022.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2022/Gabarito+N%C3%ADvel+C+2022.pdf',
    },
    'Nivel J (Junior)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2022/Prova+N%C3%ADvel+J+2022.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2022/Junior+ingl%C3%AAs+2022.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2022/Gabarito+N%C3%ADvel+J+2022.pdf',
    },
    'Nivel S (Student)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2022/Prova+N%C3%ADvel+S+2022.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2022/Student+ingl%C3%AAs+2022.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2023/Gabarito+N%C3%ADvel+S+2023.pdf',
    },
  },
  '2021' => {
    'Nivel P (Pre-Ecolier)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2021/Prova+N%C3%ADvel+P+2021.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2021/PreEcolier+ingl%C3%AAs+2021.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2021/Gabarito+N%C3%ADvel+P+2021.pdf',
    },
    'Nivel E (Ecolier)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2021/Prova+N%C3%ADvel+E+2021.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2021/Ecolier+ingl%C3%AAs+2021.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2021/Gabarito+N%C3%ADvel+E+2021.pdf',
    },
    'Nivel B (Benjamin)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2021/Prova+N%C3%ADvel+B+2021.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2021/Benjamin+ingl%C3%AAs+2021.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2021/Gabarito+N%C3%ADvel+B+2021.pdf',
    },
    'Nivel C (Cadet)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2021/Prova+N%C3%ADvel+C+2021.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2021/Cadet+ingl%C3%AAs+2021.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2021/Gabarito+N%C3%ADvel+C+2021.pdf',
    },
    'Nivel J (Junior)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2021/Prova+N%C3%ADvel+J+2021.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2021/Junior+ingl%C3%AAs+2021.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2021/Gabarito+N%C3%ADvel+J+2021.pdf',
    },
    'Nivel S (Student)' => {
      portugues: 'https://canguru-de-matematica.s3.amazonaws.com/Provas/2021/Prova+N%C3%ADvel+S+2021.pdf',
      ingles:    'https://canguru-de-matematica.s3.amazonaws.com/Ingl%C3%AAs/2021/Student+ingl%C3%AAs+2021.pdf',
      gabarito:  'https://canguru-de-matematica.s3.amazonaws.com/Gabarito/2021/Gabarito+N%C3%ADvel+S+2021.pdf',
    },
  },
}.freeze

TIPOS_DOWNLOAD = {
  portugues: 'prova',
  gabarito:  'gabarito',
}.freeze

def baixar_pdf(url, destino)
  uri = URI.parse(url)
  max_redirects = 5
  tentativa = 0

  loop do
    tentativa += 1
    if tentativa > max_redirects
      puts "  ERRO: Muitos redirecionamentos para #{File.basename(destino)}"
      return false
    end

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 15
    http.read_timeout = 60

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    case response
    when Net::HTTPRedirection
      uri = URI.parse(response['location'])
    when Net::HTTPSuccess
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

all_futures = []

DOWNLOADS.each do |ano, niveis|
  niveis.each do |nivel, urls|
    next unless nivel.include?('Pre-Ecolier') || nivel.include?('Ecolier')
    codigo_nivel = NIVEL_CODES[nivel] || nivel.downcase.gsub(/[^a-z]/, '')

    TIPOS_DOWNLOAD.each do |tipo, sufixo|
      all_futures << Concurrent::Future.execute(executor: pool) do
        total.increment
        nome_arquivo = "canguru_#{ano}_nivel_#{codigo_nivel}_#{sufixo}.pdf"
        destino = File.join(BASE_DIR, nome_arquivo)
        url = urls[tipo]

        if File.exist?(destino) && File.size(destino) > 1024
          PRINT_MUTEX.synchronize { puts "  ✅ Ja existe: #{nome_arquivo}" }
          sucesso.increment
          next
        end

        downloaded = false
        MAX_RETRIES.times do |attempt|
          begin
            PRINT_MUTEX.synchronize { print "  ⬇️  Baixando: #{nome_arquivo} (tentativa #{attempt + 1})..." }
            if baixar_pdf(url, destino)
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
  end
end

all_futures.each(&:wait)

pool.shutdown
pool.wait_for_termination

puts "\n#{'=' * 60}"
puts "Resumo: #{sucesso.value}/#{total.value} baixados com sucesso, #{falha.value} falha(s)"
puts "Arquivos salvos em: #{BASE_DIR}"
puts '=' * 60
