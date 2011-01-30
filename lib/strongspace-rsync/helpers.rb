module StrongspaceRsync
  module Helpers
    def log_file
      "#{logs_folder}/#{command_name}.log"
    end

    def logs_folder
      if running_on_a_mac?
        "#{home_directory}/Library/Logs/Strongspace"
      else
        "#{support_directory}/logs"
      end
    end

    def launchd_plist_file(profile_name)
      "#{launchd_agents_folder}/com.strongspace.#{command_name_with_profile_name(profile_name)}.plist"
    end

    def source_hash_file(profile_name)
      "#{support_directory}/#{command_name_with_profile_name(profile_name)}.lastbackup"
    end

    def configuration_file
      "#{support_directory}/#{command_name}.config"
    end

    def rsync_binary
      "rsync"
      #"/opt/local/bin/rsync"
    end

    def default_backup_path
      "#{home_directory}/Documents"
    end

    def default_space
      "backup"
    end

    def command_name
      "strongspace-rsync"
    end

    def command_name_with_profile_name(profile_name)
      "#{command_name}.#{profile_name}"
    end

  end
end
