#
# git-flow -- A collection of Git extensions to provide high-level
# repository operations for Vincent Driessen's branching model.

module GitFlow
  class Version
    GITFLOW_VERSION = 0.5

    def initialize(args)
      if args.size > 0
        puts "usage: git flow version"
      else
        puts GITFLOW_VERSION
      end
    end
  end
end
