# frozen_string_literal: true

module JekyllObsidian
  module MediaPolicy
    TYPES = {
      ".3gp" => [:audio, "audio/3gpp"],
      ".apng" => [:image, "image/apng"],
      ".avif" => [:image, "image/avif"],
      ".base" => [:download, "application/json"],
      ".bmp" => [:image, "image/bmp"],
      ".canvas" => [:download, "application/json"],
      ".flac" => [:audio, "audio/flac"],
      ".gif" => [:image, "image/gif"],
      ".jpeg" => [:image, "image/jpeg"],
      ".jpg" => [:image, "image/jpeg"],
      ".m4a" => [:audio, "audio/mp4"],
      ".mkv" => [:video, "video/x-matroska"],
      ".mov" => [:video, "video/quicktime"],
      ".mp3" => [:audio, "audio/mpeg"],
      ".mp4" => [:video, "video/mp4"],
      ".ogg" => [:audio, "audio/ogg"],
      ".ogv" => [:video, "video/ogg"],
      ".pdf" => [:pdf, "application/pdf"],
      ".png" => [:image, "image/png"],
      ".svg" => [:image, "image/svg+xml"],
      ".wav" => [:audio, "audio/wav"],
      ".webm" => [:video, "video/webm"],
      ".webp" => [:image, "image/webp"]
    }.transform_values(&:freeze).freeze

    module_function

    def kind(path)
      TYPES.dig(File.extname(path).downcase, 0)
    end

    def media_type(path, fallback: "application/octet-stream")
      TYPES.dig(File.extname(path).downcase, 1) || fallback
    end
  end
end
