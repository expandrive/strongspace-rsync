require 'yaml'
require 'find'
require 'digest'

begin
  require 'open4'
rescue LoadError
  raise "open4 gem is missing.  Please install open4: sudo gem install open4"
end

module Strongspace::Command
  class Itunes < Base

    def setup

      Strongspace::Command.run_internal("auth:check", nil)

      display "Creating a new iTunes backup profile"
      puts
      display "iTunes Library Location [#{default_itunes_library_path}]: ", false
      location = ask(default_itunes_library_path)
      display "Strongspace destination space [#{default_strongspace_destination}]: ", false
      strongspace_destination = ask(default_strongspace_destination)
      puts "Setting up backup from #{location} -> #{strongspace_destination}"

      File.open(configuration_file, 'w+' ) do |out|
        YAML.dump({'local_library_path' => location, 'strongspace_path' => "/strongspace#{strongspace_destination}"}, out)
      end

    end

    def backup

      while not load_configuration
        setup
      end

      if not (create_pid_file(command_name, Process.pid))
        display "The itunes backup process is already running"
        exit(1)
      end

      if not new_digest = has_library_changed?(@local_library_path)
        launched_by = `ps #{Process.ppid}`.split("\n")[1].split(" ").last

        if not launched_by.ends_with?("launchd")
          display "iTunes library has not changed since last backup attempt."
        end
        delete_pid_file(command_name)
        exit(0)
      end

      rsync_command = "#{rsync_binary} -e 'ssh -oServerAliveInterval=3 -oServerAliveCountMax=1' --delete -avr #{@local_library_path}/ #{strongspace.username}@#{strongspace.username}.strongspace.com:#{@strongspace_path}/"

      restart_wait = 10
      num_failures = 0

      while true do
        status = Open4::popen4(rsync_command) do
          |pid, stdin, stdout, stderr|

          display "\n\nStarting iTunes Backup: #{Time.now}"

          if not (create_pid_file("#{command_name}.rsync", pid))
            display "Couldn't start itunes backup sync, already running?"
            eixt(1)
          end

          sleep(5)
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

        delete_pid_file("#{command_name}.rsync")

        if status.exitstatus == 23 or status.exitstatus == 0
          num_failures = 0
          write_successful_backup_hash(new_digest)
          display "Successfully backed up iTunes at #{Time.now}"
          delete_pid_file(command_name)
          exit(0)
        else
          display "Error backing up - trying #{3-num_failures} more times"
          num_failures += 1
          if num_failures == 3
            puts "Failed out with status #{status.exitstatus}"
            exit(1)
          else
            sleep(1)
          end
        end

      end

      delete_pid_file(command_name)
    end

    def schedule_backup
      if not File.exist?("#{home_directory}/Library/Logs/Strongspace/")
        FileUtils.mkdir("#{home_directory}/Library/Logs/Strongspace/")
      end
      plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
      <!DOCTYPE plist PUBLIC -//Apple Computer//DTD PLIST 1.0//EN
      http://www.apple.com/DTDs/PropertyList-1.0.dtd >
      <plist version=\"1.0\">
      <dict>
          <key>Label</key>
          <string>com.strongspace.#{command_name}</string>
          <key>Program</key>
          <string>#{$PROGRAM_NAME}</string>
          <key>ProgramArguments</key>
          <array>
            <string>strongspace</string>
            <string>itunes:backup</string>
          </array>
          <key>KeepAlive</key>
          <false/>
          <key>StartInterval</key>
          <integer>60</integer>
          <key>RunAtLoad</key>
          <true/>
          <key>StandardOutPath</key>
          <string>#{home_directory}/Library/Logs/Strongspace/#{command_name}.log</string>
          <key>StandardErrorPath</key>
          <string>#{home_directory}/Library/Logs/Strongspace/#{command_name}.log</string>
      </dict>
      </plist>"

      file = File.new(launchd_plist_file, "w+")
      file.puts plist
      file.close

      r = `launchctl load -S aqua #{launchd_plist_file}`
      if r.strip.ends_with?("Already loaded")
        error "This task is aready scheduled, unload before scheduling again"
      else
        display "Scheduled #{command_name} to be run continuously"
      end
    end

    def unschedule_backup
      `launchctl unload #{launchd_plist_file}`
      FileUtils.rm(launchd_plist_file)
    end

    def backup_scheduled?
      r = `launchctl list com.strongspace.#{command_name}`
      if r.ends_with?("unknown response")
        display "#{command_name} isn't currently scheduled"
      else
        display "#{command_name} is currently scheduled for continuous backup"
      end
    end

    def logs
      if File.exist?("#{home_directory}/Library/Logs/Strongspace/#{command_name}.log")
        `open -a Console.app #{home_directory}/Library/Logs/Strongspace/#{command_name}.log`
      else
        display "No log file has been created yet, run strongspace itunes:setup to get things going"
      end
    end

    private


    def command_name
      "iTunesBackup"
    end

    def has_library_changed?(path)
      digest = recursive_digest(path)
      changed = (existing_library_hash.strip != digest.strip)
      if changed
        return digest
      else
        return nil
      end
    end

    def write_successful_backup_hash(digest)
      file = File.new(library_hash_file, "w+")
      file.puts "#{digest}"
      file.close
    end


    def recursive_digest(path)
      digest = Digest::SHA2.new(512)

      Find.find(path) do |entry|
        if File.file?(entry) or File.directory?(entry)
          stat = File.stat(entry)
          digest.update("#{entry} - #{stat.mtime} - #{stat.size}")
        end
      end

      return digest.to_s
    end

    def existing_library_hash
      if File.exist?(library_hash_file)
        f = File.open(library_hash_file)
        existing_hash = f.gets
        f.close
        return existing_hash
      end

      return ""
    end



    def load_configuration
      begin
        @configuration_hash = YAML::load_file(configuration_file)
      rescue
        return nil
      end

      @local_library_path = @configuration_hash['local_library_path']
      @strongspace_path = @configuration_hash['strongspace_path']

    end

    def launchd_plist_file
      "#{launchd_agents_folder}/com.strongspace.#{command_name}.pist"
    end

    def library_hash_file
      "#{home_directory}/.strongspace/#{command_name}.lastbackup"
    end

    def configuration_file
      "#{home_directory}/.strongspace/#{command_name}.config"
    end

    def rsync_binary
      "rsync"
      #"#{home_directory}/.strongspace/bin/rsync"
    end

    def default_itunes_library_path
      "#{home_directory}/Music/iTunes"
    end

    def default_strongspace_destination
      "/#{strongspace.username}/home/iTunes"
    end

  end
end
