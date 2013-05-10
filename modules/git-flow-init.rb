require 'optparse'
require 'ostruct'

module GitFlow
  class Init
    include Common

    def parse(args)
      @options = OpenStruct.new
      @options.force = false
      @options.defaults = false
      opts = OptionParser.new do |opts|
        opts.banner = "usage: git flow init [options]"
        opts.separator ""
        opts.separator "Options:"
        opts.on("-f", "--[no-]force", "force setting of gitflow branches, even if already configured") do |v|
          @options.force = v
        end
        opts.on("-d", "--[no-]defaults", "use default branch naming conventions") do |v|
          @options.defaults = v
        end
        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end
      end

      opts.parse!(args)
    end

    def set_git_flow_prefix(prefix, default, prompt = nil)
      if !get_git_config_item("gitflow.prefix.#{prefix}") || @options.force
        default_suggestion = get_git_config_item("gitflow.prefix.#{prefix}") || default
        prompt ||= "#{prefix.capitalize} branches?"
        print "#{prompt} [#{default_suggestion}] "
        if !@options.defaults
          answer = gets.strip
          answer = nil if answer.empty?
        else
          puts
          answer = default
        end
        answer ||= default_suggestion
        run("git config gitflow.prefix.#{prefix} '#{answer}'")
      end
    end

    def initialize(args)
      parse(args)

      unless run_successful('git rev-parse --git-dir >/dev/null 2>&1')
        run('git init')
      else
        # assure that we are not working in a repo with local changes
        git_repo_is_headless or require_clean_working_tree
      end

      # running git flow init on an already initialized repo is fine
      if gitflow_is_initialized && ! @options.force
        warn "Already initialized for gitflow."
        warn "To force reinitialization, use: git flow init -f"
        exit
      end

      # add a master branch if no such branch exists yet
      master_branch = nil
      if gitflow_has_master_configured && !@options.force
        master_branch = get_git_config_item('gitflow.branch.master')
      else
        # Two cases are distinguished:
        # 1. A fresh git repo (without any branches)
        #    We will create a new master/develop branch for the user
        # 2. Some branches do already exist
        #    We will disallow creation of new master/develop branches and
        #    rather allow to use existing branches for git-flow.
        default_suggestion = ''
        should_check_existence = true
        if git_local_branches.size.zero?
          puts "No branches exist yet. Base branches must be created now."
          should_check_existence = false
          default_suggestion = get_git_config_item('gitflow.branch.master') || 'master'
        else
          puts
          puts "Which branch should be used for bringing forth production releases?"
          git_local_branches.each do |b|
            puts " - " + b.sub(/^[* ] /, '')
          end

          [get_git_config_item('gitflow.branch.master'), 'production', 'main', 'master'].each do |guess|
            if guess and git_local_branch_exists(guess)
              default_suggestion = guess
              break
            end
          end
        end

        if @options.defaults
          warn "Using default branch names."
        end

        print "Branch name for production releases: [#{default_suggestion}] "
        if !@options.defaults; then
          answer = gets.strip
          answer = nil if answer.empty?
        else
          puts
        end
        master_branch = answer || default_suggestion

        # check existence in case of an already existing repo
        if should_check_existence
          abort "Local branch '#{master_branch}' does not exist." unless git_local_branch_exists(master_branch)
        end

        # store the name of the master branch
        run("git config gitflow.branch.master #{master_branch}")
      end

      # add a develop branch if no such branch exists yet
      develop_branch = ''
      if gitflow_has_develop_configured && !@options.force
        develop_branch = get_git_config_item('gitflow.branch.develop')
      else
        # Again, the same two cases as with the master selection are
        # considered (fresh repo or repo that contains branches)
        default_suggestion = ''
        should_check_existence = true
        branches = git_local_branches.delete_if do |b|
          b = master_branch
        end
        if branches.size.zero?
          should_check_existence = false
          default_suggestion = get_git_config_item('gitflow.branch.develop') || 'develop'
        else
          puts
          puts "Which branch should be used for integration of the \"next release\"?"
          branches.each do |b|
            puts " - " + b.sub(/^[* ] /, '')
          end
          [get_git_config_item('gitflow.branch.develop'), 'develop' 'int' 'integration' 'master'].each do |guess|
            if guess and guess != master_branch and git_local_branch_exists(guess)
              default_suggestion = guess
              break
            end
          end
        end

        print "Branch name for \"next release\" development: [#{default_suggestion}] "
        if !@options.defaults
          answer = gets.strip
          answer = nil if answer.empty?
        else
          puts
        end
        develop_branch = answer || default_suggestion

        if master_branch == develop_branch
          abort "Production and integration branches should differ."
        end

        # check existence in case of an already existing repo
        if should_check_existence
          abort "Local branch '#{develop_branch}' does not exist." unless git_local_branch_exists(develop_branch)
        end

        # store the name of the develop branch
        run("git config gitflow.branch.develop #{develop_branch}")
      end

      # Creation of HEAD
      # ----------------
      # We create a HEAD now, if it does not exist yet (in a fresh repo). We need
      # it to be able to create new branches.
      created_gitflow_branch = false
      unless run_successful('git rev-parse --quiet --verify HEAD >/dev/null 2>&1')
        run("git symbolic-ref HEAD refs/heads/#{master_branch}")
        run('git commit --allow-empty --quiet -m "Initial commit"')
        created_gitflow_branch = true
      end

      # Creation of master
      # ------------------
      # At this point, there always is a master branch: either it existed already
      # (and was picked interactively as the production branch) or it has just
      # been created in a fresh repo

      # Creation of develop
      # -------------------
      # The develop branch possibly does not exist yet.  This is the case when,
      # in a git init'ed repo with one or more commits, master was picked as the
      # default production branch and develop was "created".  We should create
      # the develop branch now in that case (we base it on master, of course)
      unless git_local_branch_exists(develop_branch)
        run("git branch --no-track #{develop_branch} #{master_branch}")
        created_gitflow_branch = true
      end

      # assert the gitflow repo has been correctly initialized
      gitflow_is_initialized

      # switch to develop branch if its newly created
      run("git checkout -q #{develop_branch}") if created_gitflow_branch

      # finally, ask the user for naming conventions (branch and tag prefixes)
      if @options.force ||
          !get_git_config_item('gitflow.prefix.feature') ||
          !get_git_config_item('gitflow.prefix.release') ||
          !get_git_config_item('gitflow.prefix.hotfix') ||
          !get_git_config_item('gitflow.prefix.support') ||
          !get_git_config_item('gitflow.prefix.versiontag')
        puts
        puts "How to name your supporting branch prefixes?"
      end
      set_git_flow_prefix('feature', 'feature/')
      set_git_flow_prefix('release', 'release/')
      set_git_flow_prefix('hotfix', 'hotfix/')
      set_git_flow_prefix('support', 'support/')
      set_git_flow_prefix('versiontag', '', 'Version tag prefix?')
      # TODO: what to do with origin?
    end

    private :parse
    private :set_git_flow_prefix
  end
end
