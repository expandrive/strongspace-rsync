Strongspace::Command::Help.group('Rsync Backup') do |group|
  group.command('rsync:backup', 'Performs a backup of a directory')
  group.command('rsync:setup', 'Create a backup profile')
  group.command('rsync:schedule_backup', 'Schedules continuous backup')
  group.command('rsync:unschedule_backup', 'Unschedules continuous backup')
  group.command('rsync:logs', 'Opens Console.app and shows the Backup log')
end