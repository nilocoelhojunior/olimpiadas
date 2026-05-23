#!/usr/bin/env ruby
# frozen_string_literal: true

# Script para baixar os PDFs dos Quebra-Cabeças do Portal da OBMEP
# Organiza por nível de dificuldade em pastas separadas

require "net/http"
require "uri"
require "nokogiri"
require "fileutils"
require "concurrent"

BASE_URL = "https://portaldaobmep.impa.br"
INDEX_URL = "#{BASE_URL}/index.php/modulo/index?a=4"
OUTPUT_DIR = File.expand_path("downloads", __dir__)

def slugify(text)
  text.unicode_normalize(:nfkd)
      .encode("ASCII", replace: "")
      .downcase
      .gsub(/[^a-z0-9]+/, "_")
      .gsub(/\A_|_\z/, "")
end
MAX_RETRIES = 3
POOL_SIZE = 5
PRINT_MUTEX = Mutex.new

def fetch_page(url)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 15
  http.read_timeout = 30

  response = http.get(uri.request_uri)
  raise "Erro HTTP #{response.code} ao acessar #{url}" unless response.is_a?(Net::HTTPSuccess)

  body = response.body
  body.force_encoding("UTF-8") unless body.encoding == Encoding::UTF_8
  Nokogiri::HTML(body, nil, "UTF-8")
end

def normalize_url(href)
  if href.start_with?("//")
    "https:#{href}"
  elsif href.start_with?("/")
    "#{BASE_URL}#{href}"
  else
    href
  end
end

def extract_pdf_url(detail_url)
  doc = fetch_page(detail_url)
  obj = doc.at_css('object[type="application/pdf"]') || doc.at_css("object[data*='.pdf']")
  return nil unless obj

  pdf_url = obj["data"]&.split("#")&.first
  return nil unless pdf_url

  normalize_url(pdf_url)
end

def sanitize_filename(name)
  name.gsub(/[\/\\:*?"<>|]/, "_").gsub(/\s+/, " ").strip
end

def download_pdf(url, filepath)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                  open_timeout: 15, read_timeout: 60) do |http|
    response = http.get(uri.request_uri)

    if response.is_a?(Net::HTTPRedirection)
      return download_pdf(normalize_url(response["location"]), filepath)
    end

    unless response.is_a?(Net::HTTPSuccess)
      puts "ERRO HTTP #{response.code}"
      return false
    end

    File.open(filepath, "wb") { |f| f.write(response.body) }
    true
  end
end

# -- MAIN --

puts "=" * 60
puts "Baixando Quebra-Cabeças do Portal da OBMEP"
puts "=" * 60

puts "\nBuscando página principal..."
doc = fetch_page(INDEX_URL)

# Estrutura: div.col-md-9 contém filhos alternados:
#   div#11 (marcador), div.panel.panel-info (wrapper nível 1, com sub-painéis),
#   div#12 (marcador), div.panel.panel-info (wrapper nível 2, com sub-painéis)
col_md9 = doc.at_css("div.col-md-9")
children = col_md9.children.select { |n| n.element? }

# Agrupa: cada div[id] é seguido pelo div.panel que contém os itens daquele nível
levels = []
children.each_with_index do |child, i|
  next unless child["id"] && !child["id"].empty?

  wrapper = children[i + 1]
  next unless wrapper&.attr("class")&.include?("panel")

  heading = wrapper.at_css(".panel-heading")&.text&.strip || "Nivel #{child["id"]}"
  inner_panels = wrapper.css(".panel")

  items = inner_panels.filter_map do |panel|
    title = panel.at_css(".panel-heading h4")&.text&.strip
    link = panel.at_css('a[href*="modulo/ver"]')
    next unless title && link

    { title: title, url: normalize_url(link["href"]) }
  end.uniq { |i| i[:url] }

  levels << { name: sanitize_filename(heading), items: items }
end

puts "Encontrados #{levels.size} níveis"

FileUtils.mkdir_p(OUTPUT_DIR)

pool = Concurrent::FixedThreadPool.new(POOL_SIZE)
sucesso = Concurrent::AtomicFixnum.new(0)
falha = Concurrent::AtomicFixnum.new(0)

levels.each_with_index do |level, level_idx|
  level_num = level_idx + 1

  PRINT_MUTEX.synchronize { puts "\n>> #{level[:name]} (#{level[:items].size} quebra-cabeças)" }

  futures = level[:items].each_with_index.map do |item, idx|
    Concurrent::Future.execute(executor: pool) do
      filename = "obmep_quebra_cabeca_nivel_#{level_num}_#{slugify(item[:title])}.pdf"
      filepath = File.join(OUTPUT_DIR, filename)
      label = "[#{idx + 1}/#{level[:items].size}] #{filename}"

      if File.exist?(filepath) && File.size(filepath) > 0
        PRINT_MUTEX.synchronize { puts "   #{label}... Já existe" }
        sucesso.increment
        next
      end

      downloaded = false
      MAX_RETRIES.times do |attempt|
        begin
          pdf_url = extract_pdf_url(item[:url])

          if pdf_url.nil?
            PRINT_MUTEX.synchronize { puts "   #{label}... PDF não encontrado" }
            break
          end

          if download_pdf(pdf_url, filepath)
            size_kb = (File.size(filepath) / 1024.0).round(1)
            PRINT_MUTEX.synchronize { puts "   #{label}... OK (#{size_kb} KB)" }
            sucesso.increment
            downloaded = true
            break
          else
            raise "download retornou false"
          end
        rescue StandardError => e
          if attempt < MAX_RETRIES - 1
            PRINT_MUTEX.synchronize { puts "   #{label}... tentativa #{attempt + 1} falhou (#{e.message}), retentando..." }
            sleep(1 * (attempt + 1))
          else
            PRINT_MUTEX.synchronize { puts "   #{label}... ERRO após #{MAX_RETRIES} tentativas: #{e.message}" }
            falha.increment
          end
        end
      end
    end
  end

  futures.each(&:wait)
end

pool.shutdown
pool.wait_for_termination

puts "\n#{"=" * 60}"
puts "Concluído! #{sucesso.value} OK, #{falha.value} falha(s)"
puts "Arquivos em: #{OUTPUT_DIR}"
puts "=" * 60
