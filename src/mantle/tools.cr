require "json"

module Mantle
  # Level 4: Individual property definitions for function parameters
  # Describes a single parameter: its type and what it represents
  struct PropertyDefinition
    include JSON::Serializable

    property type : String        # e.g., "string", "integer", "boolean"
    property description : String # Human-readable description

    def initialize(@type : String, @description : String)
    end
  end

  # Level 3: Parameters schema for function arguments
  # Defines the structure of arguments a function expects
  struct ParametersSchema
    include JSON::Serializable

    property type : String = "object" # Always "object" for parameter schemas
    property properties : Hash(String, PropertyDefinition)

    # Optional array of required parameter names
    # If a property name is in here, the LLM must provide it when calling the tool
    @[JSON::Field(emit_null: false)]
    property required : Array(String)?

    def initialize(@properties : Hash(String, PropertyDefinition), @required : Array(String)? = nil)
    end
  end

  # Level 2: Function definition
  # Describes a callable function with its name, purpose, and parameters
  struct FunctionDefinition
    include JSON::Serializable

    property name : String                 # Function identifier
    property description : String          # What the function does
    property parameters : ParametersSchema # What arguments it accepts

    def initialize(@name : String, @description : String, @parameters : ParametersSchema)
    end
  end

  # Level 1: Tool wrapper
  # Top-level container for tools sent to the LLM API
  # APIs expect an array of tools, where each tool specifies its type
  struct Tool
    include JSON::Serializable

    property type : String = "function" # Always "function" for function tools
    property function : FunctionDefinition

    def initialize(@function : FunctionDefinition)
    end
  end
end
