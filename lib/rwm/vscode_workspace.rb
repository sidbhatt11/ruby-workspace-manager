# frozen_string_literal: true

require "json"

module Rwm
  class VscodeWorkspace
    PRESERVE_KEYS = %w[settings extensions launch tasks].freeze

    attr_reader :root

    def initialize(root)
      @root = root
    end

    def file_path
      File.join(root, "#{File.basename(root)}.code-workspace")
    end

    def generate(packages)
      existing = load_existing
      folders = build_folders(packages)

      data = { "folders" => folders }

      PRESERVE_KEYS.each do |key|
        data[key] = existing[key] if existing.key?(key)
      end

      data["settings"] ||= {}

      File.write(file_path, JSON.pretty_generate(data) + "\n")
    end

    private

    def build_folders(packages)
      folders = [{ "path" => "." }]

      libs = packages.select(&:lib?).sort_by(&:name)
      apps = packages.select(&:app?).sort_by(&:name)

      (libs + apps).each do |pkg|
        folders << { "path" => pkg.relative_path(root) }
      end

      folders
    end

    def load_existing
      return {} unless File.exist?(file_path)

      JSON.parse(File.read(file_path))
    rescue JSON::ParserError
      {}
    end
  end
end
