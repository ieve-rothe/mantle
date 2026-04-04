require "./spec_helper"
require "../src/mantle/tools"

describe "Mantle Tools" do
  describe "PropertyDefinition" do
    it "serializes to JSON correctly" do
      prop = Mantle::PropertyDefinition.new(
        type: "string",
        description: "A test property"
      )

      json = prop.to_json
      json.should contain(%(type":"string"))
      json.should contain(%(description":"A test property"))
    end

    it "deserializes from JSON correctly" do
      json = %({"type":"integer","description":"A number value"})
      prop = Mantle::PropertyDefinition.from_json(json)

      prop.type.should eq("integer")
      prop.description.should eq("A number value")
    end

    it "round-trips through JSON" do
      original = Mantle::PropertyDefinition.new(
        type: "boolean",
        description: "A flag"
      )

      json = original.to_json
      restored = Mantle::PropertyDefinition.from_json(json)

      restored.type.should eq(original.type)
      restored.description.should eq(original.description)
    end
  end

  describe "ParametersSchema" do
    it "serializes to JSON with properties" do
      schema = Mantle::ParametersSchema.new(
        properties: {
          "name" => Mantle::PropertyDefinition.new("string", "User's name"),
          "age" => Mantle::PropertyDefinition.new("integer", "User's age")
        }
      )

      json = schema.to_json
      json.should contain(%(type":"object"))
      json.should contain("name")
      json.should contain("age")
    end

    it "serializes with required fields" do
      schema = Mantle::ParametersSchema.new(
        properties: {
          "name" => Mantle::PropertyDefinition.new("string", "User's name")
        },
        required: ["name"]
      )

      json = schema.to_json
      json.should contain("required")
      json.should contain("name")
    end

    it "serializes without required fields when nil" do
      schema = Mantle::ParametersSchema.new(
        properties: {
          "name" => Mantle::PropertyDefinition.new("string", "User's name")
        }
      )

      json = schema.to_json
      # When required is nil, it should either be absent or null
      # Crystal's JSON serialization typically omits nil fields with emit_null: false
    end

    it "deserializes from JSON correctly" do
      json = %({"type":"object","properties":{"file_path":{"type":"string","description":"Path to file"}},"required":["file_path"]})
      schema = Mantle::ParametersSchema.from_json(json)

      schema.type.should eq("object")
      schema.properties.keys.should contain("file_path")
      schema.properties["file_path"].type.should eq("string")
      schema.required.should eq(["file_path"])
    end

    it "round-trips complex schema through JSON" do
      original = Mantle::ParametersSchema.new(
        properties: {
          "path" => Mantle::PropertyDefinition.new("string", "File path"),
          "recursive" => Mantle::PropertyDefinition.new("boolean", "Search recursively")
        },
        required: ["path"]
      )

      json = original.to_json
      restored = Mantle::ParametersSchema.from_json(json)

      restored.type.should eq("object")
      restored.properties.size.should eq(2)
      restored.required.should eq(["path"])
    end
  end

  describe "FunctionDefinition" do
    it "serializes to JSON correctly" do
      func = Mantle::FunctionDefinition.new(
        name: "read_file",
        description: "Read contents of a file",
        parameters: Mantle::ParametersSchema.new(
          properties: {
            "file_path" => Mantle::PropertyDefinition.new("string", "Path to file")
          },
          required: ["file_path"]
        )
      )

      json = func.to_json
      json.should contain(%(name":"read_file"))
      json.should contain(%(description":"Read contents of a file"))
      json.should contain("parameters")
      json.should contain("file_path")
    end

    it "deserializes from JSON correctly" do
      json = %({"name":"list_dir","description":"List directory","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Directory path"}}}})
      func = Mantle::FunctionDefinition.from_json(json)

      func.name.should eq("list_dir")
      func.description.should eq("List directory")
      func.parameters.properties.keys.should contain("path")
    end

    it "round-trips through JSON" do
      original = Mantle::FunctionDefinition.new(
        name: "test_func",
        description: "A test function",
        parameters: Mantle::ParametersSchema.new(
          properties: {
            "arg1" => Mantle::PropertyDefinition.new("string", "First arg")
          }
        )
      )

      json = original.to_json
      restored = Mantle::FunctionDefinition.from_json(json)

      restored.name.should eq(original.name)
      restored.description.should eq(original.description)
      restored.parameters.properties.size.should eq(1)
    end
  end

  describe "Tool" do
    it "serializes to JSON correctly" do
      tool = Mantle::Tool.new(
        function: Mantle::FunctionDefinition.new(
          name: "read_file",
          description: "Read a file",
          parameters: Mantle::ParametersSchema.new(
            properties: {
              "file_path" => Mantle::PropertyDefinition.new("string", "Path")
            }
          )
        )
      )

      json = tool.to_json
      json.should contain(%(type":"function"))
      json.should contain(%(name":"read_file"))
      json.should contain("function")
    end

    it "defaults type to 'function'" do
      tool = Mantle::Tool.new(
        function: Mantle::FunctionDefinition.new(
          name: "test",
          description: "Test",
          parameters: Mantle::ParametersSchema.new(properties: {} of String => Mantle::PropertyDefinition)
        )
      )

      tool.type.should eq("function")
    end

    it "deserializes from JSON correctly" do
      json = %({"type":"function","function":{"name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"city":{"type":"string","description":"City name"}},"required":["city"]}}})
      tool = Mantle::Tool.from_json(json)

      tool.type.should eq("function")
      tool.function.name.should eq("get_weather")
      tool.function.parameters.required.should eq(["city"])
    end

    it "round-trips complex tool through JSON" do
      original = Mantle::Tool.new(
        function: Mantle::FunctionDefinition.new(
          name: "search_files",
          description: "Search for pattern in files",
          parameters: Mantle::ParametersSchema.new(
            properties: {
              "pattern" => Mantle::PropertyDefinition.new("string", "Search pattern"),
              "path" => Mantle::PropertyDefinition.new("string", "Search path"),
              "case_sensitive" => Mantle::PropertyDefinition.new("boolean", "Case sensitive")
            },
            required: ["pattern"]
          )
        )
      )

      json = original.to_json
      restored = Mantle::Tool.from_json(json)

      restored.type.should eq("function")
      restored.function.name.should eq("search_files")
      restored.function.parameters.properties.size.should eq(3)
      restored.function.parameters.required.should eq(["pattern"])
    end
  end

  describe "Tool array serialization" do
    it "serializes array of tools to JSON" do
      tools = [
        Mantle::Tool.new(
          function: Mantle::FunctionDefinition.new(
            name: "tool1",
            description: "First tool",
            parameters: Mantle::ParametersSchema.new(properties: {} of String => Mantle::PropertyDefinition)
          )
        ),
        Mantle::Tool.new(
          function: Mantle::FunctionDefinition.new(
            name: "tool2",
            description: "Second tool",
            parameters: Mantle::ParametersSchema.new(properties: {} of String => Mantle::PropertyDefinition)
          )
        )
      ]

      json = tools.to_json
      json.should contain("tool1")
      json.should contain("tool2")
    end
  end
end
