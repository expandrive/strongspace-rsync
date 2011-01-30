module StrongspaceRsync
  module Config

    def _profiles
      profiles
    end

    def profile_by_name(name)
      profiles.each do |p|
        if p['name'] == name
          return p
        end
      end
      return nil
    end

    def profiles

      if !File.exist? configuration_file
        return []
      end

      File.open(configuration_file, 'r' ) do |cfg|
        @profiles = JSON.load(cfg)['profiles']
      end

      @profiles
    end

    def add_profile(new_profile)
      save_profiles(profiles.push(new_profile))
    end

    def delete_profile(profile)
      save_profiles(profiles.reject! {|i| i['name'] == profile['name']})
    end

    def update_profile(name, new_profile)
      i = profiles.index{|profile| profile['name']== name}
      new_profiles = profiles
      new_profiles[i] = new_profile
      save_profiles(new_profiles)
    end

    def save_profiles(new_profiles)
      File.open(configuration_file, 'w+' ) do |out|
        out.write JSON.pretty_generate({'config_version' => VERSION, 'profiles' => new_profiles})
      end
    end

  end
end
