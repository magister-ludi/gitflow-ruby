#
# git-flow -- A collection of Git extensions to provide high-level
# repository operations for Vincent Driessen's branching model.

require 'fileutils'
require 'optparse'
require 'ostruct'

module GitFlow
  class Feature
    include Common
    include FileUtils

    def initialize(args)
      require_git_repo
      require_gitflow_initialized
      gitflow_load_settings
      @prefix = get_git_config_item('gitflow.prefix.feature')
      parse(args)
      eval("#{@options.command}")
    end

    def usage(opts)
      if opts
        puts opts
      else
        puts "usage: git flow feature [list] [-v]"
        puts "       git flow feature start [-F] <name> [<base>]"
        puts "       git flow feature finish [-rFk] <name|nameprefix>"
        puts "       git flow feature publish <name>"
        puts "       git flow feature track <name>"
        puts "       git flow feature diff [<name|nameprefix>]"
        puts "       git flow feature rebase [-i] [<name|nameprefix>]"
        puts "       git flow feature checkout [<name|nameprefix>]"
        puts "       git flow feature pull <remote> [<name>]"
        puts
        puts "Try 'git flow feature <subcommand> help for subcommand information'"
      end
      exit
    end

    def parse(args)
      @options = OpenStruct.new
      show_help = (args.delete('-h') || args.delete('--help') || args.delete('help')) ? 1 : nil
      if ['list', 'start', 'finish', 'publish', 'track', 'co',
          'diff', 'rebase', 'checkout', 'pull'].include?(args[0])
        @options.command = args.shift
        show_help = 2 if show_help
      else
        @options.command = 'list'
      end

      opts = OptionParser.new do |opts|
        banner = "usage: git flow feature #{@options.command} [options]"
        case @options.command
        when 'start'
          banner << ' <name> [<base>]'
        when 'finish'
          banner << ' <name|nameprefix>'
        when 'publish'
          banner << ' <name>'
        when 'track'
          banner << ' <name>'
        when 'diff'
          banner << ' [<name|nameprefix>]'
        when 'rebase'
          banner << ' [<name|nameprefix>]'
        when 'checkout'
          banner << ' [<name|nameprefix>]'
        when 'co'
          banner << ' [<name|nameprefix>]'
        when 'pull'
          banner << ' <remote> [<name>]'
        end
        opts.banner = banner
        if ['start', 'finish', 'list', 'rebase'].include?(@options.command)
          opts.separator ""
          opts.separator "Options:"
        end
        if @options.command == 'list'
          opts.on("-v", "--[no-]verbose", "verbose (more) output") do |v|
            @options.verbose = v
          end
        elsif @options.command == 'rebase'
          opts.on("-i", "--[no-]interactive", "do an interactive rebase") do |v|
            @options.interactive = v
          end
        elsif @options.command == 'start' || @options.command == 'finish'
          opts.on("-F", "--[no-]fetch", "fetch from #{@origin} before performing #{@options.command}") do |v|
            @options.fetch = v
          end
        end
        if @options.command == 'finish'
          opts.on("-r", "--rebase", "rebase instead of merge") do |v|
            @options.rebase = v
          end
          opts.on("-k", "--[no-]keep", "") do |v|
            @options.keep = v
          end
        end
      end
      opts.parse!(args)
      @remote = args.shift if @options.command == 'pull'
      @name = args.shift
      @base = args.shift
      @branch = "#{@prefix}#{@name}"
      if show_help
        usage(show_help == 2 ? opts : nil)
      end
    end

    def list
      feature_branches = git_local_branches.find_all do |b|
        b =~ /^#{@prefix}/
      end
      if feature_branches.size.zero?
        warn "No feature branches exist."
        warn ""
        warn "You can start a new feature branch:"
        warn ""
        warn "    git flow feature start <name> [<base>]"
        exit
      end
      current_branch = git_current_branch
      short_names = feature_branches.collect do |b|
        b.sub(/^#{@prefix}/, '')
      end

      # determine column width first
      width = 0
      short_names.each do |branch|
        width = [width, branch.length].max
      end
      width += 3

      short_names.each do |branch|
        fullname = "#{@prefix}#{branch}"
        base = run("git merge-base #{fullname} #{@develop_branch}").strip
        develop_sha = run("git rev-parse #{@develop_branch}").strip
        branch_sha = run("git rev-parse #{fullname}").strip
        if fullname == current_branch
          print "* "
        else
          print "  "
        end
        if @options.verbose; then
          print "%-#{width}s" % branch
          if branch_sha == develop_sha
            print "(no commits yet)"
          elsif base == branch_sha
            print "(is behind develop, may ff)"
          elsif base == develop_sha
            print "(based on latest develop)"
          else
            print "(may be rebased)"
          end
        else
          print branch
        end
        puts
      end
    end

    def require_name_arg
      if @name.nil? || @name.empty?
        warn "Missing argument <name>"
        usage
        exit
      end
    end

    def expand_nameprefix_arg
      require_name_arg
      expanded_name = gitflow_resolve_nameprefix(@name, @prefix)
      if expanded_name.is_a?(String)
        @name = expanded_name
        @branch = "#{@prefix}#{@name}"
      else
        exit
      end
    end

    def use_current_feature_branch_name
      current_branch = git_current_branch
      if current_branch =~ /^#{@prefix}/
          @branch = current_branch
        @name = @branch.sub(/^#{@prefix}/, '')
      else
        warn "The current HEAD is no feature branch."
        warn "Please specify a <name> argument."
        exit
      end
    end

    def expand_nameprefix_arg_or_current
      if @name.nil? || @name.empty?
        use_current_feature_branch_name
      else
        expand_nameprefix_arg
        require_branch("#{@prefix}#{@name}")
      end
    end

    def name_or_current
      if @name.nil? || @name.empty?
        use_current_feature_branch_name
      end
    end

    def start
      require_name_arg
      @base ||= @develop_branch

      # sanity checks
      require_branch_absent(@branch)

      # update the local repo with remote changes, if asked
      if @options.fetch
        run("git fetch -q #{@origin} #{@develop_branch}")
      end

      # if the origin branch counterpart exists, assert that the local branch
      # isn't behind it (to avoid unnecessary rebasing)
      if git_branch_exists("#{@origin}/#{@develop_branch}")
        require_branches_equal(@develop_branch, "#{@origin}/#{@develop_branch}")
      end

      # create branch
      abort "Could not create feature branch '#{@branch}'" unless
        run_successful("git checkout -b #{@branch} #{@base}")

      puts
      puts "Summary of actions:"
      puts "- A new branch '#{@branch}' was created, based on '#{@base}'"
      puts "- You are now on branch '#{@branch}'"
      puts
      puts "Now, start committing on your feature. When done, use:"
      puts
      puts "     git flow feature finish #{@name}"
      puts
    end

    def finish
      expand_nameprefix_arg

      # sanity checks
      require_branch(@branch)

      merge_dir = File.join(@dot_git_dir, '.gitflow')
      merge_info = File.join(merge_dir, "MERGE_BASE")
      # detect if we're restoring from a merge conflict
      if File.exist?(merge_info)
        #
        # TODO: detect that we're working on the correct branch here!
        # The user need not necessarily have given the same @name twice here
        # (although he/she should).
        #

        # TODO: git_is_clean_working_tree() should provide an alternative
        # exit code for "unmerged changes in working tree", which we should
        # actually be testing for here
        if git_is_clean_working_tree
          finish_base = File.readlines(merge_info).strip

          # Since the working tree is now clean, either the user did a
          # succesfull merge manually, or the merge was cancelled.
          # We detect this using git_is_branch_merged_into()
          if git_is_branch_merged_int(@branch, finish_base)
            File.unlink(merge_info)
            helper_finish_cleanup
            exit
          else
            # If the user cancelled the merge and decided to wait until later,
            # that's fine. But we have to acknowledge this by removing the
            # MERGE_BASE file and continuing normal execution of the finish
            File.unlink(merge_info)
          end
        else
          puts
          puts "Merge conflicts not resolved yet, use:"
          puts "    git mergetool"
          puts "    git commit"
          puts
          puts "You can then complete the finish by running it again:"
          puts "    git flow feature finish #{@name}"
          puts
          exit
        end
      end

      # sanity checks
      require_clean_working_tree

      # update local repo with remote changes first, if asked
      if git_remote_branches.include?("#{@origin}/#{@branch}")
        if @options.fetch
          run("git fetch -q #{@origin} #{@branch}")
        end
      end

      if git_remote_branches.include?("#{@origin}/#{@branch}")
        require_branches_equal(@branch, "#{@origin}/#{@branch}")
      end
      if git_remote_branches.include?("#{@origin}/#{@develop_branch}")
        require_branches_equal(@develop_branch, "#{@origin}/#{@develop_branch}")
      end

      # if the user wants to rebase, do that first
      if @options.rebase
        if !run_successful("git flow feature rebase #{@name} #{@develop_branch}")
          warn "Finish was aborted due to conflicts during rebase."
          warn "Please finish the rebase manually now."
          warn "When finished, re-run:"
          warn "    git flow feature finish '#{@name}' '#{@develop_branch}'"
          exit
        end
      end

      # merge into @base
      run("git checkout #{@develop_branch}")
      if run("git rev-list -n2 #{@develop_branch}..#{@branch}").split("\n").size == 1
        merge_result = run_successful("git merge --ff #{@branch}")
      else
        merge_result = run_successful("git merge --no-ff #{@branch}")
      end

      if !merge_result
        # oops.. we have a merge conflict!
        # write the given @develop_branch to a temporary file (we need it later)
        mkdir_p(merge_dir)
        File.open(merge_info, 'w') do |out|
          out.puts @develop_branch
        end
        puts
        puts "There were merge conflicts. To resolve the merge conflict manually, use:"
        puts "    git mergetool"
        puts "    git commit"
        puts
        puts "You can then complete the finish by running it again:"
        puts "    git flow feature finish #{@name}"
        puts
        exit
      end

      # when no merge conflict is detected, just clean up the feature branch
      helper_finish_cleanup
    end

    def helper_finish_cleanup
      # sanity checks
      require_branch(@branch)
      require_clean_working_tree

      # delete branch
      if @options.fetch
        run("git push #{@origin} :refs/heads/#{@branch}")
      end

      unless @options.keep
        run("git branch -d #{@branch}")
      end

      puts
      puts "Summary of actions:"
      puts "- The feature branch '#{@branch}' was merged into '#{@develop_branch}'"
      #puts "- Merge conflicts were resolved"                # TODO: Add this line when it's supported
      if @options.keep
        puts "- Feature branch '#{@branch}' is still available"
      else
        puts "- Feature branch '#{@branch}' has been removed"
      end
      puts "- You are now on branch '#{@develop_branch}'"
      puts
    end

    def publish
      expand_nameprefix_arg

      # sanity checks
      require_clean_working_tree
      require_branch(@branch)
      run("git fetch -q #{@origin}")
      require_branch_absent("#{@origin}/#{@branch}")

      # create remote branch
      run("git push #{@origin} #{@branch}:refs/heads/#{@branch}")
      run("git fetch -q #{@origin}")

      # configure remote tracking
      run("git config branch.#{@branch}.remote #{@origin}")
      run("git config branch.#{@branch}.merge refs/heads/#{@branch}")
      run("git checkout #{@branch}")

      puts
      puts "Summary of actions:"
      puts "- A new remote branch '#{@branch}' was created"
      puts "- The local branch '#{@branch}' was configured to track the remote branch"
      puts "- You are now on branch '#{@branch}'"
      puts
    end

    def track
      require_name_arg

      # sanity checks
      require_clean_working_tree
      require_branch_absent(@branch)
      run("git fetch -q #{@origin}")
      require_branch("#{@origin}/#{@branch}")

      # create tracking branch
      run("git checkout -b #{@branch} #{@origin}/#{@branch}")

      puts
      puts "Summary of actions:"
      puts "- A new remote tracking branch '#{@branch}' was created"
      puts "- You are now on branch '#{@branch}'"
      puts
    end

    def diff
      if @name.nil? or @name.empty?
        abort "Not on a feature branch. Name one explicitly." unless
          git_current_branch =~ /^#{@prefix}/

        @base = run("git merge-base #{@develop_branch} HEAD").strip
        puts run("git diff #{@base}")
      else
        expand_nameprefix_arg
        @base = run("git merge-base #{@develop_branch} #{@branch}").strip
        puts run("git diff #{@base}..#{@branch}")
      end
    end

    def checkout
      if @name.nil? or @name.empty?
        abort "Name a feature branch explicitly."
      else
        expand_nameprefix_arg
        run("git checkout #{@branch}")
      end
    end
    alias :co :checkout

    def rebase
      expand_nameprefix_arg_or_current
      warn "Will try to rebase '#{@name}'..."
      require_clean_working_tree
      require_branch(@branch)

      run("git checkout -q #{@branch}")
      if @options.interactive
        puts "Interactive rebase not available yet."
        puts "You are currently on branch '#{@branch}'"
        puts
        puts "To rebase, please run"
        puts "    git rebase -i #{@develop_branch}"
      else
        run("git rebase #{@develop_branch}")
      end
    end

    def avoid_accidental_cross_branch_action
      current_branch = git_current_branch
      if @branch != current_branch
        warn "Trying to pull from '#{@branch}' while currently on branch '#{current_branch}'."
        warn "To avoid unintended merges, git-flow aborted."
        false
      else
        true
      end
    end

    def pull
      if @remote.nil? or @remote.empty?
        abort "Name a remote explicitly."
      end
      name_or_current

      # To avoid accidentally merging different feature branches into each other,
      # abort if the current feature branch differs from the requested @name
      # argument.
      current_branch = git_current_branch
      if current_branch =~ /^#{@prefix}/
          # we are on a local feature branch already, so @branch must be equal to
          # the current branch
          abort unless avoid_accidental_cross_branch_action
      end

      require_clean_working_tree

      if git_branch_exists(@branch)
        # Again, avoid accidental merges
        abort unless avoid_accidental_cross_branch_action

        # we already have a local branch called like this, so simply pull the
        # remote changes in
        abort "Failed to pull from remote '#{@remote}'." unless
          run_successful("git pull -q #{@remote} #{@branch}")
        puts "Pulled #{@remote}'s changes into @branch."
      else
        # setup the local branch clone for the first time
        abort "Fetch failed." unless
          run_successful("git fetch -q #{@remote} #{@branch}")     # stores in FETCH_HEAD
        abort "Branch failed." unless
          run_successful("git branch --no-track #{@branch} FETCH_HEAD")
        abort "Checking out new local branch failed." unless
          run_successful("git checkout -q #{@branch}")
        puts "Created local branch #{@branch} based on #{@remote}'s #{@branch}."
      end
    end
    private :usage
    private :parse
    private :list
    private :require_name_arg
    private :expand_nameprefix_arg
    private :use_current_feature_branch_name
    private :expand_nameprefix_arg_or_current
    private :name_or_current
    private :start
    private :finish
    private :helper_finish_cleanup
    private :publish
    private :track
    private :diff
    private :checkout
    private :rebase
    private :avoid_accidental_cross_branch_action
    private :pull
  end
end
