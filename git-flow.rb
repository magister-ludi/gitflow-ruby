#!/usr/bin/env ruby
#
# git-flow -- A collection of Git extensions to provide high-level
# repository operations for Vincent Driessen's branching model.

module GitFlow
  GITFLOW_DIR = File.dirname(__FILE__)
  @@verbose = 0
  require(File.join(GITFLOW_DIR, 'modules', "gitflow-common.rb"))

  def GitFlow.verbose
    return @@verbose
  end

  def self.usage
    puts "usage: git flow [-debug] [-show] <subcommand>"
    puts
    puts "Available subcommands are:"
    puts "   init      Initialize a new git repo with support for the branching model."
    puts "   feature   Manage your feature branches."
    puts "   release   Manage your release branches."
    puts "   hotfix    Manage your hotfix branches."
    puts "   support   Manage your support branches."
    puts "   version   Shows version information."
    puts
    puts "Try 'git flow <subcommand> help' for details."
    exit
  end

  def self.run(args)
    commands = Dir[File.join(GITFLOW_DIR, 'modules', "git-flow-*.rb")].collect do |mod|
      File.basename(mod, '.rb').sub(/^git-flow-/, '')
    end
    if args.size.zero? or (args.size == 1 and args[0] =~ /^-{0,2}help$/)
      usage
    else
      if commands.include?(args[0]) or commands.include?(args[1])
        if commands.include?(args[1])
          args[0], args[1] = args[1], args[0]
        end
        subcommand = args.shift
        show_help = (args.delete('-h') || args.delete('--help') || args.delete('help')) ? true : false
        args.push('--help') if show_help
        @@verbose = 1 if args.delete('-show')
        @@verbose = 2 if args.delete('-debug')
        require(File.join(GITFLOW_DIR, 'modules', "git-flow-#{subcommand}.rb"))
        eval("#{subcommand.capitalize}.new(args)")
      else
        usage
      end
    end
  end
end

GitFlow.run(ARGV) if __FILE__ == $0
