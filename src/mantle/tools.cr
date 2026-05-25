# mantle/tools.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "json"

module Mantle
  # Defines an individual property within a function's parameters schema.
  #
  # Describes a single parameter, including its type and what it represents.
  struct PropertyDefinition
    include JSON::Serializable

    # Represents the type of the property (e.g., "string", "integer", "boolean").
    property type : String

    # Represents the human-readable description of the property.
    property description : String

    # Creates a property definition with the specified *type* and *description*.
    def initialize(@type : String, @description : String)
    end
  end

  # Defines the schema structure of arguments a function expects.
  struct ParametersSchema
    include JSON::Serializable

    # Represents the type of the schema, which is always "object" for parameter schemas.
    property type : String = "object"

    # Represents the hash mapping parameter names to their `PropertyDefinition` values.
    property properties : Hash(String, PropertyDefinition)

    # Represents the optional list of required parameter names.
    #
    # If a property name is present in this list, the LLM must provide it when calling the tool.
    @[JSON::Field(emit_null: false)]
    property required : Array(String)?

    # Creates a parameters schema with the specified *properties* and *required* list.
    def initialize(@properties : Hash(String, PropertyDefinition), @required : Array(String)? = nil)
    end
  end

  # Defines a callable function, containing its name, description, and parameters schema.
  struct FunctionDefinition
    include JSON::Serializable

    # Represents the function identifier.
    property name : String

    # Represents the description of what the function does.
    property description : String

    # Represents the `ParametersSchema` defining what arguments the function accepts.
    property parameters : ParametersSchema

    # Creates a function definition with the specified *name*, *description*, and *parameters*.
    def initialize(@name : String, @description : String, @parameters : ParametersSchema)
    end
  end

  # Represents a container wrapper for tools sent to the LLM API.
  #
  # LLM APIs expect an array of tools, where each tool specifies its type.
  struct Tool
    include JSON::Serializable

    # Represents the tool type, which is always "function" for function tools.
    property type : String = "function"

    # Represents the `FunctionDefinition` defining the tool function.
    property function : FunctionDefinition

    # Creates a tool wrapper around the specified *function*.
    def initialize(@function : FunctionDefinition)
    end
  end
end
