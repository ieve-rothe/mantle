# mantle/tools/builtin/notify_send.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "../tools"

module Mantle::Tools::Builtin
  module NotifySend
    def self.definition : FunctionDefinition
      FunctionDefinition.new(
        name: "notify_send",
        description: "Send a desktop notification to the user",
        parameters: ParametersSchema.new(
          properties: {
            "message" => PropertyDefinition.new(
              type: "string",
              description: "The message content of the notification"
            ),
          },
          required: ["message"]
        )
      )
    end

    def self.create(bot_name : String = "Assistant", icon : String? = nil) : Tool
      Tool.new(definition) do |arguments|
        execute(arguments, bot_name: bot_name, icon: icon)
      end
    end

    def self.execute(arguments : Hash(String, JSON::Any), bot_name : String = "Assistant", icon : String? = nil) : String
      message = arguments["message"]?.try(&.as_s?)

      unless message
        return {success: false, error: "Missing required parameter: message"}.to_json
      end

      if message.strip.starts_with?("-")
        return {
          success: false,
          error:   "Security violation: message cannot start with a hyphen.",
          message: message,
        }.to_json
      end

      args = [bot_name]

      if icon
        args << "--icon=#{icon}"
      end

      args << "--"
      args << message

      begin
        status = Process.run("notify-send", args)
        if status.success?
          {
            success:              true,
            message:              "Notification sent successfully",
            notification_message: message,
          }.to_json
        else
          {
            success: false,
            error:   "Error sending notification. Exit code: #{status.exit_code}",
            message: message,
          }.to_json
        end
      rescue ex
        {
          success: false,
          error:   "Error executing notify-send: #{ex.message}",
          message: message,
        }.to_json
      end
    end
  end
end
