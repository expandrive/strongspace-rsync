Strongspace::Command::Help.group('iTunes Backup') do |group|
  group.command('rsync:backup', 'Performs a backup of iTunes')
  group.command('rsync:setup', 'Create a backup profile for iTunes')
  group.command('rsync:schedule_backup', 'Schedules continuous backup')
  group.command('rsync:unschedule_backup', 'Unschedules continuous backup')
  group.command('rsync:logs', 'Opens Console.app and shows the iTunes Backup log')
end