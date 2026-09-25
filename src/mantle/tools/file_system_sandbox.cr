# mantle/tools/file_system_sandbox.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

module Mantle::Tools
  # Enforces file system security and path boundaries for file and directory tools.
  #
  # Validates all file system access against allowed paths and autonomous zones,
  # handles symlink-safe path expansion, and manages automatic file backups.
  class FileSystemSandbox
    property working_directory : String
    property allowed_paths : Array(String)?
    property autonomous_zone_paths : Array(String)?
    property file_backup_count : Int32

    def initialize(
      @working_directory : String,
      @allowed_paths : Array(String)? = nil,
      @autonomous_zone_paths : Array(String)? = nil,
      @file_backup_count : Int32 = 3,
    )
    end

    # Resolves a path to an absolute path, expanding relative paths against `working_directory`.
    def resolve_path(path : String) : String
      if path.starts_with?("/")
        File.expand_path(path)
      else
        File.expand_path(path, @working_directory)
      end
    end

    # Checks if an absolute path is permitted for reading or directory listing.
    def path_allowed?(absolute_path : String) : Bool
      if allowed = @allowed_paths
        allowed.any? { |allowed_path| is_subpath?(absolute_path, allowed_path) }
      else
        is_subpath?(absolute_path, @working_directory)
      end
    end

    # Checks if an absolute path is permitted for writing (within configured autonomous zones).
    def path_in_autonomous_zone?(absolute_path : String) : Bool
      if zone_paths = @autonomous_zone_paths
        zone_paths.any? { |zone_path| is_subpath?(absolute_path, zone_path) }
      else
        false
      end
    end

    # Checks if `path` is identical to or within `base` directory, preventing symlink traversal escapes.
    def is_subpath?(path : String, base : String) : Bool
      expanded_path = safe_realpath(path)
      expanded_base = safe_realpath(base)

      return true if expanded_path == expanded_base

      base_with_separator = expanded_base.ends_with?(File::SEPARATOR) ? expanded_base : expanded_base + File::SEPARATOR
      expanded_path.starts_with?(base_with_separator)
    end

    # Safely resolves a path to its real path, even if it or its parents don't exist yet.
    def safe_realpath(path : String) : String
      if File.exists?(path) || File.symlink?(path)
        begin
          File.realpath(path)
        rescue
          File.expand_path(path)
        end
      else
        parent = File.dirname(path)
        if parent == path
          File.expand_path(path)
        else
          File.join(safe_realpath(parent), File.basename(path))
        end
      end
    end

    # Creates a timestamped backup for `absolute_path` and rotates old backups exceeding `file_backup_count`.
    def create_file_backup(absolute_path : String)
      timestamp = Time.utc.to_s("%Y%m%d%H%M%S")
      backup_path = "#{absolute_path}.#{timestamp}.bak"
      File.copy(absolute_path, backup_path)

      backup_limit = @file_backup_count
      dir = File.dirname(absolute_path)
      filename = File.basename(absolute_path)

      if Dir.exists?(dir)
        backups = Dir.children(dir)
          .select { |f| f.starts_with?("#{filename}.") && f.ends_with?(".bak") }
          .map { |f| File.join(dir, f) }
          .sort

        if backups.size > backup_limit
          backups_to_delete = backups.size - backup_limit
          backups[0, backups_to_delete].each do |old_backup|
            File.delete(old_backup) if File.exists?(old_backup)
          end
        end
      end
    end
  end
end
