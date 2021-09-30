module ChefDocBuilder
  class DummyResource
    attr_reader :actions, :name, :properties, :unified_mode, :uses

    def initialize(name)
      @actions = []
      @name = name
      @properties = []
      @unified_mode = nil
      @uses = []
    end

    def action(arg)
      @actions.push(arg)
    end

    def action_class(&block)
      nil
    end

    def lazy(&block)
      nil
    end

    def load_current_value(&block)
      nil
    end

    def load_from_file(file)
      raise unless File.exist?(file) && File.file?(file)

      file_content = File.read(file)

      # Skip (attemping) to load any included libraries
      file_content.gsub!(/^include/, '#include')

      instance_eval(file_content, File.basename(file), 1)

      true
    end

    def property(name, type = NOT_PASSED, **options)
      property_hash = {
        name: name,
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
  end
end
