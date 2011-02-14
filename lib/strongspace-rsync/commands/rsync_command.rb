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

      profiles = _profiles

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

      if new_profile = ask_for_new_rsync_profile
        add_profile(new_profile)

        if args[3] and args[3] == "schedule"
          schedule
        end
      end

      return new_profile
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

      if !profile_exist?(profile_name)
        display "Please supply the name of the profile you'd like to run"
        self.list
        return false
      end

      if not (create_pid_file("#{command_name_with_profile_name(profile_name)}", Process.pid))
        display "The backup process for #{profile_name} is already running"
        exit(1)
      end

      if global_value('paused') or (profile_value(profile_name, 'paused') == true)
        display "This backup has been paused"
        return true
      end

      if profile_value(profile_name, 'last_successful_backup').blank?
        validate_destination_space(profile_value(profile_name, 'strongspace_path').split("/")[3], create=true)
        begin
          strongspace.mkdir("/#{strongspace.username}/#{computername}#{profile_value(profile_name, 'local_source_path')}")
        rescue RestClient::Conflict => e
        end

        if profile_value(profile_name, 'last_successful_backup').blank?
          total_bytes = `du -ks '#{profile_value(profile_name, 'local_source_path')}'`.split("\t")[0].to_i * 1024
          set_profile_value(profile_name, total_bytes, 'local_source_size')
        end

      elsif not new_digest = source_changed?(profile_name)
        launched_by = `ps #{Process.ppid}`.split("\n")[1].split(" ").last

        if not launched_by.ends_with?("launchd")
          display "backup target has not changed since last backup attempt."
        end

        set_profile_value(profile_name, DateTime.now.to_s, 'last_successful_backup')

        delete_pid_file("#{command_name_with_profile_name(profile_name)}")
        return
      end

      restart_wait = 10
      num_failures = 0

      puts "checking size to upload #{rsync_command_size(profile_name)}"
      sizeCheckOutput = `#{rsync_command_size(profile_name)}`


      totalToUpload = profile_value(profile_name, "totalToUpload")

      if totalToUpload.blank? or totalToUpload == 0
        totalToUpload = sizeCheckOutput.match(/Total transferred file size: [0-9,]+ bytes/).to_s.match(/[0-9,]+/).to_s.gsub(",","").to_i
      end
      puts "Total to upload #{totalToUpload}"

      set_profile_value(profile_name, totalToUpload.to_f, 'totalToUpload')

      # Set this to avoid divide by zero, for now
      if totalToUpload == 0
        totalToUpload = 1
      end

      bytesUploaded = profile_value(profile_name, "bytesUploaded")
      if bytesUploaded.blank?
        bytesUploaded = 0
      end

      bytesCounter = bytesUploaded

      while true do
        status = Open4::popen4(rsync_command(profile_name)) do
          |pid, stdin, stdout, stderr|

          display "\n\nStarting Strongspace Backup: #{Time.now}"
          display "rsync command:\n\t#{rsync_command(profile_name)}"

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
            progressTime = Time.now

            while not f.eof?
              lines = f.readpartial(1000).gsub("\r", "\n")

              if lines.include?("\n")
                lines.split("\n").each do |line|
                  if line.include? "100%" and line.include?("(xfr#")
                    bytesUploaded += line.split(" ")[0].gsub(",","").to_i
                    bytesCounter = bytesUploaded
                  elsif line.include? "%" and !line.include? "100%"
                    bytesCounter = bytesUploaded + line.split(" ")[0].gsub(",","").to_i
                  end

                  if (Time.now - 1) > progressTime
                    progressTime = Time.now
                    if bytesCounter > bytesUploaded
                      percentage = (bytesCounter.to_f/totalToUpload.to_f)
                      if percentage > 1
                        percentage = 1
                      end
                      set_profile_value(profile_name, bytesUploaded.to_f, 'bytesUploaded')
                      set_profile_value(profile_name, percentage, 'percent_uploaded')
                    else
                      percentage = (bytesUploaded.to_f/totalToUpload.to_f)
                      if percentage > 1
                        percentage = 1
                      end
                      set_profile_value(profile_name, bytesUploaded.to_f, 'bytesUploaded')
                      set_profile_value(profile_name, percentage, 'percent_uploaded')
                    end
                  end

                end
              end
            end

        }

          threads.each { |aThread|  aThread.join }
        end

        delete_pid_file("#{command_name_with_profile_name(profile_name)}.rsync")

        if status.exitstatus == 23 or status.exitstatus == 0
          num_failures = 0
          display "Successfully backed up at #{Time.now}"

          profile = profile_by_name(profile_name)

          set_profile_value(profile_name, 0, 'totalToUpload')
          set_profile_value(profile_name, 0, 'bytesUploaded')
          set_profile_value(profile_name, 1, 'percent_uploaded')
          set_profile_value(profile_name, new_digest, 'last_successful_backup_hash')
          set_profile_value(profile_name, DateTime.now.to_s, 'last_successful_backup')

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

      if process_running?("#{command_name_with_profile_name(profile_name)}")
        return true
      else
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
        <integer>600</integer>
        <key>RunAtLoad</key>
        <true/>
        <key>StandardOutPath</key>
        <string>#{log_file}</string>
        <key>StandardErrorPath</key>
        <string>#{log_file}</string>
        <key>EnvironmentVariables</key>
        <dict>
        <key>STRONGSPACE_DISPLAY</key>
        <string>logging</string>
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

        profile['active'] = true
        update_profile(profile_name, profile)

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
          profile['active'] = false
          update_profile(profile_name, profile)
        end
      else  # Assume we're running on linux/unix
        CronEdit::Crontab.Remove "strongspace-#{command_name}-#{profile_name}"
      end

      display "Unscheduled continuous backup"

    end
    alias :unschedule_backup :unschedule

    def stop_scheduled
      profile_name = args.first
      profile = profile_by_name(profile_name)

      if profile.blank?
        display "Please supply the name of the profile you'd like to stop"
        return false
      end

      if running_on_windows?
        error "Scheduling currently isn't supported on Windows"
        return
      end

      if running_on_a_mac?
        if File.exist? launchd_plist_file(profile_name)
          `launchctl stop 'com.strongspace.#{command_name_with_profile_name(profile_name)}'`
        end
      end

      display "Stopped continuous backup"
    end

    def restart_scheduled
      profile_name = args.first
      profile = profile_by_name(profile_name)

      if profile.blank?
        display "Please supply the name of the profile you'd like to stop"
        return false
      end

      if running_on_windows?
        error "Scheduling currently isn't supported on Windows"
        return
      end

      if running_on_a_mac?
        if File.exist? launchd_plist_file(profile_name)
          `launchctl start 'com.strongspace.#{command_name_with_profile_name(profile_name)}'`
        end
      end

      display "Stopped continuous backup"
    end

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
        return false
      else
        return true
      end

    end

    def pause_all
      set_global_value(true, 'paused')
      profiles = _profiles
      Strongspace::Command.run_internal("spaces:unschedule_snapshots", [profiles.first['strongspace_path'].split("/")[3]])


      profiles.each do |p|
        args[0] = p['name']
        if scheduled?
          stop_scheduled
        end
      end

    end

    def unpause_all
      profiles = _profiles
      Strongspace::Command.run_internal("spaces:schedule_snapshots", [profiles.first['strongspace_path'].split("/")[3]])
      set_global_value(false, 'paused')


      profiles.each do |p|
        args[0] = p['name']
        if scheduled?
          restart_scheduled
        end
      end
    end

    def all_paused?
      return global_value('paused')
    end

    def unschedule_all
      profiles = _profiles
      Strongspace::Command.run_internal("spaces:unschedule_snapshots", [profiles.first['strongspace_path'].split("/")[3]])
      profiles.each do |p|
        args[0] = p['name']
        if scheduled?
          unschedule
        end
      end
    end

    def reschedule_all
      profiles = _profiles

      # set the computername in the credentials file

      if File.exist? credentials_file
        n = File.read(credentials_file).split("\n")[2]
        if n.blank?
          name = profiles.first['strongspace_path'].split("/")[3]
          File.open(credentials_file, 'a') do |f|
            f.puts name
          end
        end

        cache_quota
      end

      Strongspace::Command.run_internal("spaces:unschedule_snapshots", [profiles.first['strongspace_path'].split("/")[3]])
      profiles.each do |p|
        args[0] = p['name']

        if scheduled?
          unschedule
          schedule
        end
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

    def cache_quota
      begin
        f = strongspace.filesystem
        set_global_value(f['quota_gib'], "quota_gib")
        set_global_value(f['used_gib'], "used_gib")
      rescue
      end
    end

    def generate_defaults
      if !File.exist? configuration_file
        Strongspace::Command.run_internal("rsync:create", ["Desktop", "#{home_directory}/Desktop"])
        Strongspace::Command.run_internal("rsync:create", ["Documents", "#{home_directory}/Documents"])
        Strongspace::Command.run_internal("rsync:create", ["Dropbox", "#{home_directory}/Dropbox"]) if File.exist? "#{home_directory}/Dropbox"
      end
    end

    private
    def ask_for_new_rsync_profile
      # Name
      name = args.first

      if profile_by_name(name)
        raise CommandFailed, "Couldn't Add Folder to Backups|This backup name is already in use"
      end

      display "Creating a new strongspace backup profile named #{args.first}"

      if args[1].blank? and args[2].blank?
        # Source
        display "Location to backup [#{default_backup_path}]: ", false
        location = ask(default_backup_path)
        location = Pathname(location).cleanpath.to_s
        # Destination
        display "Strongspace destination [/strongspace/#{strongspace.username}/#{computername}#{location}]: ", false
        dest = ask("/strongspace/#{strongspace.username}/#{computername}#{location}")
      else
        location = args[1]
        location = Pathname(location).cleanpath.to_s
        if args[2]
          dest = args[2]
        else
          dest = "/strongspace/#{strongspace.username}/#{computername}#{location}"
        end
      end

      _profiles.each do |profile|
        source = Pathname(profile['local_source_path']).cleanpath.to_s
        if source.starts_with? location or location.starts_with? source
          raise CommandFailed, "Couldn't Add Folder to Backups|Nested backups are not currently permitted"
        end
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

    def rsync_command(profile_name)
      if File.exist? self.gui_ssh_key
        rsync_flags = "-e 'ssh -oServerAliveInterval=3 -oServerAliveCountMax=1 -o UserKnownHostsFile=#{credentials_folder}/known_hosts -o PreferredAuthentications=publickey -i #{self.gui_ssh_key}' "
      else
        rsync_flags = "-e 'ssh -oServerAliveInterval=3 -oServerAliveCountMax=1' "
      end
      rsync_flags << "-avz -P "
      rsync_flags << "--delete " unless profile_value(profile_name, 'keep_remote_files')

      local_source_path = profile_value(profile_name, 'local_source_path')

      if not File.file?(local_source_path)
        local_source_path = "#{local_source_path}/"
      end

      rsync_command_string = "#{rsync_binary}  #{rsync_flags} '#{local_source_path}' \"#{strongspace.username}@#{strongspace.username}.strongspace.com:'#{profile_value(profile_name, 'strongspace_path')}'\""

      puts "Excludes: #{profile['excludes']}" if DEBUG

      if profile_value(profile_name, 'excludes')
        for pattern in profile_value(profile_name, 'excludes').each do
          rsync_command_string << " --exclude \"#{pattern}\""
        end
      end

      return rsync_command_string
    end

    def rsync_command_size(profile_name)
      if ENV["RACK_ENV"] == "production" and !File.exist? self.gui_ssh_key
        Strongspace::Command.run_internal("keys:generate_for_gui",[])
      end


      if File.exist? self.gui_ssh_key
        rsync_flags = "-e 'ssh -oServerAliveInterval=3 -oServerAliveCountMax=1 -o UserKnownHostsFile=#{credentials_folder}/known_hosts -o PreferredAuthentications=publickey -i #{self.gui_ssh_key}' "
      else
        rsync_flags = "-e 'ssh -oServerAliveInterval=3 -oServerAliveCountMax=1' "
      end
      rsync_flags << "-az --stats --dry-run "
      rsync_flags << "--delete " unless profile_value(profile_name, 'keep_remote_files')

      local_source_path = profile_value(profile_name, 'local_source_path')

      if not File.file?(local_source_path)
        local_source_path = "#{local_source_path}/"
      end

      rsync_command_string = "#{rsync_binary}  #{rsync_flags} '#{local_source_path}' \"#{strongspace.username}@#{strongspace.username}.strongspace.com:'#{profile_value(profile_name, 'strongspace_path')}'\""

      puts "Excludes: #{profile['excludes']}" if DEBUG

      if profile_value(profile_name, 'excludes')
        for pattern in profile_value(profile_name, 'excludes').each do
          rsync_command_string << " --exclude \"#{pattern}\""
        end
      end

      return rsync_command_string
    end


    def source_changed?(profile_name)
      digest = recursive_digest(profile_value(profile_name, 'local_source_path'))

      changed = profile_value(profile_name, 'last_successful_backup_hash') != digest.to_s.strip
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
