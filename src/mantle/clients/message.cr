# mantle/clients/message.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

module Mantle
  struct Message
    include JSON::Serializable

    property role : String
    property content : String?

    @[JSON::Field(emit_null: false)]
    property tool_calls : Array(Mantle::Clients::ToolCall)?

    @[JSON::Field(emit_null: false)]
    property tool_call_id : String?

    def initialize(@role : String, @content : String? = nil, @tool_calls : Array(Mantle::Clients::ToolCall)? = nil, @tool_call_id : String? = nil)
    end
  end
end
