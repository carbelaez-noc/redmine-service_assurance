# frozen_string_literal: true

require 'openssl'
require 'base64'
require 'json'

module FibrazoServiceAssurance
  # Token NetBox cifrado en reposo. El servidor solo guarda texto cifrado
  # (setting netbox_token_enc); la llave vive en un archivo 600 fuera de git.
  # La UI nunca muestra el valor: solo estado configurado/ausente.
  class NetboxTokenStore
    KEY_PATH = File.expand_path('../../.netbox_key', __dir__).freeze

    def self.key
      unless File.readable?(KEY_PATH)
        File.binwrite(KEY_PATH, OpenSSL::Random.random_bytes(32))
        File.chmod(0o600, KEY_PATH)
      end
      k = File.binread(KEY_PATH)
      raise 'llave NetBox inválida' unless k.bytesize == 32
      k
    end

    def self.save(plain)
      plain = plain.to_s.strip
      return false if plain.empty?
      cipher = OpenSSL::Cipher.new('aes-256-gcm')
      cipher.encrypt
      cipher.key = key
      iv = cipher.random_iv
      cipher.auth_data = 'sa-netbox'
      ct = cipher.update(plain) + cipher.final
      blob = { 'iv' => Base64.strict_encode64(iv), 'tag' => Base64.strict_encode64(cipher.auth_tag),
               'ct' => Base64.strict_encode64(ct) }.to_json
      s = Setting.plugin_fibrazo_service_assurance
      s['netbox_token_enc'] = blob
      Setting.plugin_fibrazo_service_assurance = s
      true
    end

    def self.read
      blob = Setting.plugin_fibrazo_service_assurance['netbox_token_enc'].to_s
      return legacy_path_read if blob.empty?
      h = JSON.parse(blob)
      decipher = OpenSSL::Cipher.new('aes-256-gcm')
      decipher.decrypt
      decipher.key = key
      decipher.iv = Base64.strict_decode64(h['iv'])
      decipher.auth_tag = Base64.strict_decode64(h['tag'])
      decipher.auth_data = 'sa-netbox'
      decipher.update(Base64.strict_decode64(h['ct'])) + decipher.final
    rescue StandardError
      nil
    end

    def self.configured?
      !read.to_s.empty?
    end

    # Compatibilidad transitoria con la ruta de archivo (fase anterior).
    def self.legacy_path_read
      path = Setting.plugin_fibrazo_service_assurance['netbox_token_path'].to_s.strip
      return nil if path.empty? || !File.readable?(path)
      File.read(path).strip.presence
    end
  end
end
