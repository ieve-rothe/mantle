# mantle/tools/builtin.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "./builtin/*"

module Mantle::Tools::Builtin
  # Returns standard Tool instances for all built-in tools, wired to the given sandbox.
  def self.all(
    sandbox : FileSystemSandbox,
    bot_name : String = "Assistant",
    notify_icon : String? = nil,
  ) : Array(Tool)
    [
      ReadFile.create(sandbox),
      WriteFile.create(sandbox),
      ListDirectory.create(sandbox),
      SearchFiles.create(sandbox),
      NotifySend.create(bot_name: bot_name, icon: notify_icon),
    ]
  end
end
