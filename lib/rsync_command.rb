require 'yaml'
require 'find'
require 'digest'
require 'open4'
require 'cronedit'
require 'date'

DEBUG = false

module Strongspace::Command
  class Rsync < Base
    VERSION = "0.0.2"

    # Display the version of the plugin and also return it
    def version
      display "#{command_name} v#{VERSION}"
      VERSION
    end

    # Displays a list of the available rsync profiles
    def list
      display "Available rsync backup profiles:"

      if profiles(reload=true).blank?
        return []
      end

      profiles.each do |key, value|
        display key
      end

      return profiles
    end

    # create a new profile by prompting the user
    def create
      if args.blank?
        error "Please supply the name for the profile you'd like to create"
      end

      Strongspace::Command.run_internal("auth:check", nil)

      display "Creating a new strongspace backup profile named #{args.first}"

      new_profile = ask_for_new_rsync_profile

      save_profiles(profiles.merge(new_profile))
    end
    alias :setup :create

    # delete a profile by prompting the user
    def delete

      profile_name = args.first
      profile = profiles[profile_name]

      if profile.blank?
        display "Please supply the name of the profile you'd like to delete"
        self.list
        return false
      end
      profiles.delete(profile_name)
      save_profiles(profiles)
      display "#{profile_name} has been deleted"
    end

    # run a specific rsync backup profile
    def run
      profile_name = args.first
      profile = profiles[profile_name]

      if profile.blank?
        display "Please supply the name of the profile you'd like to run"
        self.list
        return false
      end

      if not (create_pid_file("#{command_name_with_profile_name(profile_name)}", Process.pid))
        display "The backup process for #{profile_name} is already running"
        exit(1)
      end

      if not new_digest = source_changed?(profile_name,profile)
        launched_by = `ps #{Process.ppid}`.split("\n")[1].split(" ").last

        if not launched_by.ends_with?("launchd")
          display "backup target has not changed since last backup attempt."
        end

        profile['last_successful_backup'] = DateTime.now.to_s
        save_profiles(profiles.merge({profile_name => profile}))

        delete_pid_file("#{command_name_with_profile_name(profile_name)}")
        return
      end


      restart_wait = 10
      num_failures = 0

      while true do
        status = Open4::popen4(rsync_command(profile)) do
          |pid, stdin, stdout, stderr|

          display "\n\nStarting Strongspace Backup: #{Time.now}"
          display "rsync command:\n\t#{rsync_command(profile)}" if DEBUG

          if not (create_pid_file("#{command_name_with_profile_name(profile_name)}.rsync", pid))
            display "Couldn't start backup sync, already running?"
            exit(1)
          end

          sleep(5) if num_failures
          threads = []


          threads << Thread.new(stderr) { |f|
            while not f.eof?
              line = f.gets.strip
              if not line.starts_with?("rsync: failed to set permissions on") and not line.starts_with?("rsync error: some files could not be transferred (code 23) ") and not line.starts_with?("rsync error: some files/attrs were not transferred (see previous errors)")
                puts "error: #{line}" unless line.blank?
              end
            end
          }

          threads << Thread.new(stdout) { |f|
            while not f.eof?
              line = f.gets.strip
              puts "#{line}" unless line.blank?
            end
          }


          threads.each { |aThread|  aThread.join }

        end

        delete_pid_file("#{command_name_with_profile_name(profile_name)}.rsync")

        if status.exitstatus == 23 or status.exitstatus == 0
          num_failures = 0
          write_successful_backup_hash(profile_name, new_digest)
          display "Successfully backed up at #{Time.now}"

          profile['last_successful_backup'] = DateTime.now.to_s
          save_profiles(profiles.merge({profile_name => profile}))


          delete_pid_file("#{command_name_with_profile_name(profile_name)}")

          return true
        else
          display "Error backing up - trying #{3-num_failures} more times"
          num_failures += 1
          if num_failures == 3
            puts "Failed out with status #{status.exitstatus}"
            return false
          else
            sleep(1)
          end
        end

      end

      delete_pid_file("#{command_name_with_profile_name(profile_name)}")
      return true
    end
    alias :backup :run


    def schedule
      profile_name = args.first
      profile = profiles[profile_name]

      if profile.blank?
        display "Please supply the name of the profile you'd like to schedule"
        self.list
        return false
      end

      if not File.exist?(logs_folder)
        FileUtils.mkdir(logs_folder)
      end

      if running_on_windows?
        error "Scheduling currently isn't supported on Windows"
        return
      end

      if running_on_a_mac?
        plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <!DOCTYPE plist PUBLIC -//Apple Computer//DTD PLIST 1.0//EN
        http://www.apple.com/DTDs/PropertyList-1.0.dtd >
        <plist version=\"1.0\">
        <dict>
            <key>Label</key>
            <string>com.strongspace.#{command_name_with_profile_name(profile_name)}</string>
            <key>Program</key>
            <string>#{$PROGRAM_NAME}</string>
            <key>ProgramArguments</key>
            <array>
              <string>strongspace</string>
              <string>rsync:run</string>
              <string>#{profile_name}</string>
            </array>
            <key>KeepAlive</key>
            <false/>
            <key>StartInterval</key>
            <integer>60</integer>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardOutPath</key>
            <string>#{log_file}</string>
            <key>StandardErrorPath</key>
            <string>#{log_file}</string>
        </dict>
        </plist>"

        file = File.new(launchd_plist_file(profile_name), "w+")
        file.puts plist
        file.close

        r = `launchctl load -S aqua #{launchd_plist_file(profile_name)}`
        if r.strip.ends_with?("Already loaded")
          error "This task is aready scheduled, unload before scheduling again"
          return
        end
        display "Scheduled #{profile_name} to be run continuously"
      else  # Assume we're running on linux/unix
        begin
          CronEdit::Crontab.Add  "strongspace-#{command_name}-#{profile_name}", "0,5,10,15,20,25,30,35,40,45,52,53,55 * * * * #{$PROGRAM_NAME} rsync:run #{profile_name} >> #{log_file} 2>&1"
        rescue Exception => e
          error "Error setting up schedule: #{e.message}"
        end
        display "Scheduled #{profile_name} to be run every five minutes"
      end

    end
    alias :schedule_backup :schedule

    def unschedule
      profile_name = args.first
      profile = profiles[profile_name]

      if profile.blank?
        display "Please supply the name of the profile you'd like to unschedule"
        self.list
        return false
      end

      if running_on_windows?
        error "Scheduling currently isn't supported on Windows"
        return
      end

      if running_on_a_mac?
        `launchctl unload #{launchd_plist_file(profile_name)}`
        FileUtils.rm(launchd_plist_file(profile_name))
      else  # Assume we're running on linux/unix
        CronEdit::Crontab.Remove "strongspace-#{command_name}-#{profile_name}"
      end

      display "Unscheduled continuous backup"

    end
    alias :unschedule_backup :unschedule

    def scheduled?
      profile_name = args.first
      profile = profiles[profile_name]

      if profile.blank?
        display "Please supply the name of the profile you'd like to query"
        self.list
        return false
      end

      r = `launchctl list com.strongspace.#{command_name}.#{profile_name} 2>&1`

      if r.ends_with?("unknown response\n")
        display "#{profile_name} isn't currently scheduled"
      else
        display "#{profile_name} is scheduled for continuous backup"
      end
    end

    def logs
      if File.exist?(log_file)
        if running_on_windows?
          error "Scheduling currently isn't supported on Windows"
          return
        end
        if running_on_a_mac?
          `open -a Console.app #{log_file}`
        else
          system("/usr/bin/less less #{log_file}")
        end
      else
        display "No log file has been created yet, run strongspace rsync:setup to get things going"
      end
    end


    def _profiles
      profiles
    end

    private


    def ask_for_new_rsync_profile

      # Name
      name = args.first

      # Source
      display "Location to backup [#{default_backup_path}]: ", false
      location = ask(default_backup_path)

      # Destination
      display "Strongspace destination space [#{default_space}]: ", false
      space = ask(default_space)

      validate_destination_space(space)

      strongspace_destination = "#{strongspace.username}/#{space}"

      return {name => {'local_source_path' => location, 'strongspace_path' => "/strongspace/#{strongspace_destination}" } }
    end

    def validate_destination_space(space)
      # TODO: this validation flow could be made more friendly
      if !valid_space_name?(space) then
        puts "Invalid space name #{space}. Aborting."
        exit(-1)
      end

      if !space_exist?(space) then
        display "#{strongspace.username}/#{space} does not exist. Would you like to create it? [y]: ", false
        if ask('y') == 'y' then
          strongspace.create_space(space, 'backup')
        else
          puts "Aborting"
          exit(-1)
        end
      end

      if !backup_space?(space) then
        puts "#{space} is not a 'backup'-type space. Aborting."
        exit(-1)
      end
    end

    def command_name
      "RsyncBackup"
    end

    def command_name_with_profile_name(profile_name)
      "#{command_name}.#{profile_name}"
    end

    def rsync_command(profile)
      rsync_flags = "-e 'ssh -oServerAliveInterval=3 -oServerAliveCountMax=1' "
      rsync_flags << "-avz "
      rsync_flags << "--delete " unless profile['keep_remote_files']
      rsync_flags << "--partial --progress" if profile['progressive_transfer']

      local_source_path = profile['local_source_path']

      if not File.file?(local_source_path)
        local_source_path = "#{local_source_path}/"
      end

      rsync_command_string = "#{rsync_binary}  #{rsync_flags} #{local_source_path} #{strongspace.username}@#{strongspace.username}.strongspace.com:#{profile['strongspace_path']}/"
      puts "Excludes: #{profile['excludes']}" if DEBUG

      if profile['excludes']
        for pattern in profile['excludes'].each do
          rsync_command_string << " --exclude \"#{pattern}\""
        end
      end

      return rsync_command_string
    end

    def source_changed?(profile_name, profile)
      digest = recursive_digest(profile['local_source_path'])
      #digest.update(profile.hash.rto_s) # also consider config changes
      changed = (existing_source_hash(profile_name).strip != digest.to_s.strip)
      if changed
        return digest
      else
        return nil
      end
    end

    def write_successful_backup_hash(profile_name, digest)
      file = File.new(source_hash_file(profile_name), "w+")
      file.puts "#{digest}"
      file.close
    end

    def recursive_digest(path)
      # TODO: add excludes to digest computation
      digest = Digest::SHA2.new(512)

      Find.find(path) do |entry|
        if File.file?(entry) or File.directory?(entry)
          stat = File.stat(entry)
          digest.update("#{entry} - #{stat.mtime} - #{stat.size}")
        end
      end

      return digest
    end

    def existing_source_hash(profile_name)
      if File.exist?(source_hash_file(profile_name))
        f = File.open(source_hash_file(profile_name))
        existing_hash = f.gets
        f.close
        return existing_hash
      end

      return ""
    end


    def profiles(reload=false)
      return @profiles if (!reload and @profiles)

      begin
        config = YAML::load_file(configuration_file)
        config_version = config['config_version']
        config.reject! {|k,v| k == 'config_version'}
      rescue
        return {}
      end

      if config_version != VERSION
        save_profiles({'default' => config})
        return profiles
      end

      @profiles = config['profiles']
    end

    def save_profiles(new_profiles)
      File.open(configuration_file, 'w+' ) do |out|
        YAML.dump({'config_version' => VERSION, 'profiles' => new_profiles}, out)
      end
    end

    def log_file
      "#{logs_folder}/#{command_name}.log"
    end

    def logs_folder
      if running_on_a_mac?
        "#{home_directory}/Library/Logs/Strongspace"
      else
        "#{home_directory}/.strongspace/logs"
      end
    end

    def launchd_plist_file(profile_name)
      "#{launchd_agents_folder}/com.strongspace.#{command_name_with_profile_name(profile_name)}.plist"
    end

    def source_hash_file(profile_name)
      "#{home_directory}/.strongspace/#{command_name_with_profile_name(profile_name)}.lastbackup"
    end

    def configuration_file
      "#{home_directory}/.strongspace/#{command_name}.config"
    end

    def rsync_binary
      "rsync"
      #"#{home_directory}/.strongspace/bin/rsync"
    end

    def default_backup_path
      "#{home_directory}/Documents"
    end

    def default_space
      "backup"
    end

  end
end
