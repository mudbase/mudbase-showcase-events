# frozen_string_literal: true

require "securerandom"

module Mudbase
  # A random, unguessable single-use check-in code, mirroring the reference web app's
  # `generateQrToken()` (`crypto.randomUUID().replace(/-/g, "")`, 32 hex chars / 122 bits of
  # entropy). `SecureRandom.hex(16)` yields the same 32-hex-character shape at 128 bits - not a
  # security credential in the cryptographic sense (this is a demo ticketing app, not a payments
  # system), just collision-resistant enough for a QR check-in token.
  module QrToken
    def self.generate
      SecureRandom.hex(16)
    end
  end
end
