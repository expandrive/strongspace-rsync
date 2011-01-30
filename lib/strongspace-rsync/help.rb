Strongspace::Command::Help.group('Rsync Backup') do |group|
  group.command('rsync:list', 'List backup profiles')
  group.command('rsync:run <name>', 'Run a backup profile')
  group.command('rsync:create <name>', 'Create a backup profile')
  group.command('rsync:delete <name> [remove_data]', 'Delete a backup profile, [remove_data=>(yes|no)]]')
  group.command('rsync:schedule <name>', 'Schedules continuous backup')
  group.command('rsync:unschedule <name>', 'Unschedules continuous backup')
  group.command('rsync:logs', 'Opens Console.app and shows the Backup log')
end