# frozen_string_literal: true

require 'net/http'
require 'json'

module FibrazoServiceAssurance
  # Cliente exclusivamente GET contra NetBox. TLS verificado, timeout y reintentos.
  class NetboxClient
    TIMEOUT = 15
    RETRIES = 2

    class Error < StandardError; end

    def initialize(base_url:, token:)
      raise Error, 'base_url requerida' if base_url.to_s.strip.empty?
      raise Error, 'token requerido' if token.to_s.strip.empty?
      @base = base_url.to_s.sub(%r{/+\z}, '')
      @token = token.to_s.strip
    end

    def circuits(limit: 50)
      fetch_all('/api/circuits/circuits/', limit: limit)
    end

    def providers(limit: 50)
      fetch_all('/api/circuits/providers/', limit: limit)
    end

    private

    def fetch_all(path, limit:)
      out, offset = [], 0
      loop do
        page = get("#{path}?limit=#{limit}&offset=#{offset}")
        results = page['results'] || []
        out.concat(results)
        break unless page['next'] && results.any?
        offset += limit
        raise Error, 'paginación excede 5000 registros' if offset > 5000
      end
      out
    end

    def get(path)
      uri = URI.join(@base + '/', path.sub(%r{\A/+}, ''))
      raise Error, 'solo HTTPS' unless uri.scheme == 'https'
      attempts = 0
      begin
        attempts += 1
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT
        req = Net::HTTP::Get.new(uri.request_uri, 'Authorization' => "Token #{@token}", 'Accept' => 'application/json')
        res = http.request(req)
        raise Error, "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      rescue JSON::ParserError => e
        raise Error, "respuesta no JSON: #{e.message}"
      rescue Error
        raise
      rescue StandardError => e
        retry if attempts <= RETRIES && (sleep(2 * attempts) || true)
        raise Error, "conexión: #{e.class} #{e.message.to_s[0, 120]}"
      end
    end
  end
end
