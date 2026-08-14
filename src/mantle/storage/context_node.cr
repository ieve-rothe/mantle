# mantle/storage/context_node.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "json"
require "uuid"
require "../clients/message"

module Mantle::Storage
  # Module converter for RFC3339 time formatting to ensure byte-identical round trips.
  module RFC3339Converter
    def self.from_json(pull : JSON::PullParser) : Time
      Time::Format::RFC_3339.parse(pull.read_string)
    end

    def self.to_json(value : Time, json : JSON::Builder) : Nil
      json.string(Time::Format::RFC_3339.format(value))
    end
  end

  # Represents generation parameters for reproducible-ish replay.
  struct GenerationParams
    include JSON::Serializable

    @[JSON::Field(emit_null: false)]
    property model : String?

    @[JSON::Field(emit_null: false)]
    property quant : String?

    @[JSON::Field(emit_null: false)]
    property temperature : Float64?

    @[JSON::Field(emit_null: false)]
    property top_p : Float64?

    @[JSON::Field(emit_null: false)]
    property top_k : Int32?

    @[JSON::Field(emit_null: false)]
    property repeat_penalty : Float64?

    @[JSON::Field(emit_null: false)]
    property seed : Int32?

    def initialize(
      @model : String? = nil,
      @quant : String? = nil,
      @temperature : Float64? = nil,
      @top_p : Float64? = nil,
      @top_k : Int32? = nil,
      @repeat_penalty : Float64? = nil,
      @seed : Int32? = nil
    )
    end
  end

  # Represents a discrete node in the conversational transcript graph.
  # Class (reference type) to prevent accidental copy-mutation bugs.
  class ContextNode
    include JSON::Serializable

    property id : String
    property parent_id : String?
    property message : Mantle::Message

    @[JSON::Field(emit_null: false)]
    property turn_id : String?

    @[JSON::Field(converter: Mantle::Storage::RFC3339Converter)]
    property ts : Time

    property token_count : Int32

    @[JSON::Field(emit_null: false)]
    property assembled_context_sha : String?

    @[JSON::Field(emit_null: false)]
    property generation : GenerationParams?

    def initialize(
      @message : Mantle::Message,
      @token_count : Int32,
      @parent_id : String? = nil,
      @turn_id : String? = nil,
      @id : String = UUID.random.to_s,
      @ts : Time = Time.utc,
      @assembled_context_sha : String? = nil,
      @generation : GenerationParams? = nil
    )
    end
  end
end
