module Strongspace::Command
  DEBUG = false

  class Rsync < Base
    include StrongspaceRsync::Helpers
    include StrongspaceRsync::Config

    # Display the version of the plugin and also return it
    def version
      display "#{command_name} v#{StrongspaceRsync::VERSION}"
      StrongspaceRsync::VERSION
    end

    # Displays a list of the available rsync profiles
    def list
      display "Available rsync backup profiles:"

      if profiles.blank?
        return []
      end

      profiles.each do |profile|
        display profile['name']
      end

      return profiles
    end

    # create a new profile by prompting the user
    def create
      if args.blank?
        error "Please supply the name for the profile you'd like to create"
      end

      Strongspace::Command.run_internal("auth:check", nil)

      new_profile = ask_for_new_rsync_profile

      add_profile(new_profile)
    end
    alias :setup :create

    # delete a profile by prompting the user
    def delete
      profile = profile_by_name(args.first)

      if profile.blank?
        display "Please supply the name of the profile you'd like to delete"
        self.list
        return false
      end

      if args[1] == "yes"
        puts profile['strongspace_path'][12..-1]
        begin
          strongspace.rm(profile['strongspace_path'][12..-1])
        rescue
        end
      end

      delete_profile(profile)


      display "#{args.first} has been deleted"
    end

    # run a specific rsync backup profile
    def run
      profile_name = args.first
      profile = profile_by_name(profile_name)

      if profile.blank?
        display "Please supply the name of the profile you'd like to run"
        self.list
        return false
      end

      if not (create_pid_file("#{command_name_with_profile_name(profile_name)}", Process.pid))
        display "The backup process for #{profile_name} is already running"
        exit(1)
      end

      if profile['last_successful_backup'].blank?
        validate_destination_space(profile['strongspace_path'].split("/")[3], create=true)
        begin
          strongspace.mkdir("/#{strongspace.username}/#{hostname}#{profile['local_source_path']}")
        rescue RestClient::Conflict => e
        end
      end


      if not new_digest = source_changed?(profile_name,profile)
        launched_by = `ps #{Process.ppid}`.split("\n")[1].split(" ").last

        if not launched_by.ends_with?("launchd")
          display "backup target has not changed since last backup attempt."
        end


        profile = profile_by_name(profile_name)
        profile['last_successful_backup'] = DateTime.now.to_s

        update_profile(profile_name, profile)

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
          display "Successfully backed up at #{Time.now}"

          profiles = profile_by_name(profile_name)

          profile['last_successful_backup_hash'] = new_digest
          profile['last_successful_backup'] = DateTime.now.to_s

          update_profile(profile_name, profile)

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

    def running?
      profile_name = args.first
      profile = profile_by_name(profile_name)

      if profile.blank?
        display "Please supply the name of the profile you'd like to query"
        self.list
        return false
      end

      if process_running?("#{command_name_with_profile_name(profile_name)}")
        display "#{profile_name} is currently running"
        return true
      else
        display "#{profile_name} is not currently running"
        return false
      end

      return false
    end

    def schedule
      profile_name = args.first
      profile = profile_by_name(profile_name)

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
            <string>#{support_directory}/gems/bin/strongspace</string>
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
            <key>EnvironmentVariables</key>
            <dict>
              <key>GEM_PATH</key>
              <string>#{support_directory}/gems</string>
              <key>GEM_HOME</key>
              <string>#{support_directory}/gems</string>
              <key>RACK_ENV</key>
              <string>production</string>
            </dict>

        </dict>
        </plist>"

        file = File.new(launchd_plist_file(profile_name), "w+")
        file.puts plist
        file.close

        r = `launchctl load -S aqua '#{launchd_plist_file(profile_name)}'`
        if r.strip.ends_with?("Already loaded")
          error "This task is aready scheduled, unload before scheduling again"
          return
        end

        Strongspace::Command.run_internal("spaces:schedule_snapshots", [profile['strongspace_path'].split("/")[3]])

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
      profile = profile_by_name(profile_name)

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
        if File.exist? launchd_plist_file(profile_name)
          `launchctl unload '#{launchd_plist_file(profile_name)}'`
          FileUtils.rm(launchd_plist_file(profile_name))
        end
      else  # Assume we're running on linux/unix
        CronEdit::Crontab.Remove "strongspace-#{command_name}-#{profile_name}"
      end

      display "Unscheduled continuous backup"

    end
    alias :unschedule_backup :unschedule

    def scheduled?
      profile_name = args.first
      profile = profile_by_name(profile_name)

      if profile.blank?
        display "Please supply the name of the profile you'd like to query"
        self.list
        return false
      end

      r = `launchctl list 'com.strongspace.#{command_name}.#{profile_name}' 2>&1`

      if r.ends_with?("unknown response\n")
        display "#{profile_name} isn't currently scheduled"
        return false
      else
        display "#{profile_name} is scheduled for continuous backup"
        return true
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


    private


    def ask_for_new_rsync_profile

      # Name
      name = args.first

      if profile_by_name(name)
        display "This backup name is already in use"
        return
      end

      display "Creating a new strongspace backup profile named #{args.first}"

      if args[1].blank? and args[2].blank?
        # Source
        display "Location to backup [#{default_backup_path}]: ", false
        location = ask(default_backup_path)

        # Destination
        display "Strongspace destination [/strongspace/#{strongspace.username}/#{hostname}#{location}]: ", false
        dest = ask("/strongspace/#{strongspace.username}/#{hostname}#{location}")
      else
        location = args[1]
        dest = args[2]
      end

      return {'name' => name, 'local_source_path' => location, 'strongspace_path' => dest }
    end

    def validate_destination_space(space, create=false)
      # TODO: this validation flow could be made more friendly

      if !space_exist?(space)
        if not create
          display "#{strongspace.username}/#{space} does not exist. Would you like to create it? [y]: ", false
          if ask('y') != 'y'
            puts "Aborting"
            exit(-1)
          end
        end
        strongspace.create_space(space, 'backup')
      end

      if !backup_space?(space)
        puts "#{space} is not a 'backup'-type space. Aborting."
        exit(-1)
      end

    end

    def rsync_command(profile)

      if File.exist? self.gui_ssh_key
        rsync_flags = "-e 'ssh -oServerAliveInterval=3 -oServerAliveCountMax=1 -o UserKnownHostsFile=#{credentials_folder}/known_hosts -o PreferredAuthentications=publickey -i #{self.gui_ssh_key}' "
      else
        rsync_flags = "-e 'ssh -oServerAliveInterval=3 -oServerAliveCountMax=1' "
      end
      rsync_flags << "-avz "
      rsync_flags << "--delete " unless profile['keep_remote_files']
      rsync_flags << "--partial --progress" if profile['progressive_transfer']

      local_source_path = profile['local_source_path']

      if not File.file?(local_source_path)
        local_source_path = "#{local_source_path}/"
      end

      rsync_command_string = "#{rsync_binary}  #{rsync_flags} '#{local_source_path}' \"#{strongspace.username}@#{strongspace.username}.strongspace.com:'#{profile['strongspace_path']}'\""

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
      changed = profile['last_successful_backup_hash'] != digest.to_s.strip
      if changed
        return digest
      else
        return nil
      end
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



  end
end
