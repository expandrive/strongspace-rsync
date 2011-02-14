require 'tempfile'

module StrongspaceRsync
  module Config

    def profile_by_name(name=args.first)
      profiles = _profiles
      profiles.each do |p|
        if p['name'] == name
          return p
        end
      end
      return nil
    end

    def profile_value(profile_name, key_name)
      p = profile_by_name(profile_name)
      return p[key_name]
    end

    def set_profile_value(profile_name, value, key_name)
       p = profile_by_name(profile_name)
       p[key_name] = value
       update_profile(profile_name, p)
    end

    def global_value(key_name)
      begin
        c = _config_dictionary
      rescue
        c = {}
      end
      return c[key_name]
    end

    def set_global_value(value, key_name)
      c = _config_dictionary
      c['config_version'] = Strongspace::VERSION
      c[key_name] = value
      _write_config_dictionary(c)
    end

    def set_global_values(hash)
      c = _config_dictionary
      c['config_version'] = Strongspace::VERSION
      c.merge!(hash)
      _write_config_dictionary(c)
    end

    def profile_exist?(profile_name)
      profile_by_name(profile_name) != nil
    end

    def add_profile(new_profile)
      profiles = _profiles.push(new_profile)
      set_global_values('profiles' => profiles)
    end

    def delete_profile(profile)
      profiles = _profiles
      profiles = profiles.reject {|i| i['name'] == profile['name']}
      set_global_values('profiles' => profiles)
    end

    def update_profile(name, new_profile)
      profiles = _profiles
      i = profiles.index{|profile| profile['name']== name}
      profiles[i] = new_profile
      set_global_values('profiles' => profiles)
    end


    def _profiles
      begin
        r = global_value('profiles')
        if r.blank?
          return []
        end
      rescue
        r = []
      end

      return r
    end

    def _config_dictionary
      contents = nil
      begin
        File.open(configuration_file, "r", 0644) do |c|
          contents = c.readlines.join("\n")
        end

        return JSON.load(contents)
      rescue
      end
      return {}
    end

    def _write_config_dictionary(dict)
      new_config = JSON.pretty_generate(dict)
      if new_config.length < 10
        display "Strongspace: Error writing config file, please notify developer"
        return
      end
      out = Tempfile.new("rsync-config")
      out.write new_config
      out.close
      FileUtils.mv out.path, configuration_file
      out.unlink
    end

  end
end
