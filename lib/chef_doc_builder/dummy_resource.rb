module ChefDocBuilder
  # Class to gather information from a custom resource
  class DummyResource
    attr_reader :actions, :name, :libraries, :properties, :uses, :provide, :requires

    INCLUDE_REGEX = /^include (?<lib>.*)$/
    private_constant :INCLUDE_REGEX

    def initialize(name)
      @actions = []
      @libraries = []
      @name = name
      @properties = []
      @unified_mode = nil
      @uses = []
      @provide = []
      @requires = []
    end

    def action(arg)
      @actions.push(arg)
    end

    def action_class
      nil
    end

    def lazy
      nil
    end

    def load_current_value
      nil
    end

    def load_from_file(file)
      raise "File #{file} does not exist" unless File.exist?(file) && File.file?(file)

      file_content = File.read(file)

      # Match the libraries include-ed
      @libraries.concat(file_content.scan(/^(?:\s+)?include (?<lib>.*)$/).flatten)
      # Skip (attemping) to load any included libraries
      file_content.gsub!(/^include/, '#include')

      instance_eval(file_content, File.basename(file), 1)

      self
    end

    def property(name, type = NOT_PASSED, **options)
      property_hash = {
        name:,
        type: Array(type),
      }.merge(options)

      @properties.push(property_hash)
    end

    def unified_mode(val)
      @unified_mode = val
    end

    def use(partial)
      @uses.push(partial)
    end

    def provides(partial)
      @provide.push(partial)
    end

    def require(gem)
      @requires.push(gem)
    end
  end
end
