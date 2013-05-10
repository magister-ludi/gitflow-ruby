#
# git-flow -- A collection of Git extensions to provide high-level
# repository operations for Vincent Driessen's branching model.
require 'optparse'
require 'ostruct'

module GitFlow
  class Hotfix
    include Common

    def initialize(args)
      require_git_repo
      require_gitflow_initialized
      gitflow_load_settings
      @version_prefix = get_git_config_item('gitflow.prefix.versiontag')
      @prefix = get_git_config_item('gitflow.prefix.hotfix')
      parse(args)
      eval("#{@options.command}")
    end

    def usage(opts)
      if opts
        puts opts
      else
         puts "usage: git flow hotfix [list] [-v]"
        puts "       git flow hotfix start [-F] <version> [<base>]"
        puts "       git flow hotfix finish [-Fsumpkt] <version>"
      end
      exit
    end

    def parse(args)
      @options = OpenStruct.new
      show_help = (args.delete('-h') || args.delete('--help') || args.delete('help')) ? 1 : nil
      if ['list', 'start', 'finish'].include?(args[0])
        @options.command = args.shift
        show_help = 2 if show_help
      else
        @options.command = 'list'
      end
      opts = OptionParser.new do |opts|
        banner = "usage: git flow feature #{@options.command} [options]"
        case @options.command
        when 'start'
          banner << ' <version> [<base>]'
        when 'finish'
          banner << ' <version>'
        end
        opts.banner = banner
        opts.separator ""
        opts.separator "Options:"
        if @options.command == 'list'
          opts.on("-v", "--[no-]verbose", "verbose (more) output") do |v|
            @options.verbose = v
          end
        elsif @options.command == 'start' || @options.command == 'finish'
          opts.on("-F", "--[no-]fetch", "fetch from #{@origin} before performing #{@options.command}") do |v|
            @options.fetch = v
          end
        elsif @options.command == 'finish'
          opts.on("-s", "--[no-]sign", "sign the hotfix tag cryptographically") do |v|
            @options.sign = v
          end
          opts.on("-u", "--use-key GPG_KEY", "use the given GPG_KEY for the digital signature (implies -s)") do |v|
            @options.signingkey = v
          end
          opts.on("-m", "--message MESSAGE", "use tag message MESSAGE") do |v|
            @options.message = v
          end
          opts.on("-p", "--[no-]push", "push to #{@origin} after performing #{@options.command}") do |v|
            @options.push = v
          end
          opts.on("-k", "--[no-]keep", "") do |v|
            @options.keep = v
          end
          opts.on("-t", "--[no-]tag", "tag this hotfix (defaults to true)") do |v|
            @options.tag = v
          end
        end
      end
      opts.parse!(args)
      if ['start', 'finish'].include?(@options.command)
        @version = args.shift
        unless @version
          warn "Missing argument <version>" unless show_help
          usage(opts)
        end
        @base = args.shift
        @branch = @prefix + @version
      end
      if show_help
        usage(show_help == 2 ? opts : nil)
      end
    end

    def list
      hotfix_branches = git_local_branches.find_all do |b|
        b =~ /^#{@prefix}/
      end
      if hotfix_branches.size.zero?
        warn "No hotfix branches exist."
        warn
        warn "You can start a new hotfix branch:"
        warn
        warn "    git flow hotfix start <version> [<base>]"
        warn
        exit
      end
      current_branch = git_current_branch
      short_names = hotfix_branches.collect do |b|
        b.sub(/^#{@prefix}/, '')
      end
      # determine column width first
      width = 0
      short_names.each do |branch|
        width = [width, branch.length].max
      end
      width += 3

      short_names.each do |branch|
        fullname = @prefix + branch
        base = run("git merge-base #{fullname} #{@master_branch}").strip
        master_sha = run("git rev-parse #{@master_branch}").strip
        branch_sha = run("git rev-parse #{fullname}").strip
        if fullname == current_branch
          print "* "
        else
          print "  "
        end
        if @options.verbose
          print "%-#{width}s" % branch
          if branch_sha == master_sha
            print "(no commits yet)"
          else
            tagname = run("git name-rev --tags --no-undefined --name-only #{base}").strip
            if tagname.empty?
              nicename = run("git rev-parse --short #{base}").strip
            else
              nicename = tagname
            end
            print "(based on #{nicename})"
          end
        else
          print branch
        end
        puts
      end
    end

    def require_base_is_on_master
      run("git branch --no-color --contains #{@base} 2>/dev/null").split("\n").each do |b|
        return if b.sub(/^[* ] /, '') == @master_branch
      end
      abort "fatal: Given base '#{@base}' is not a valid commit on '#{@master_branch}'."
    end

    def require_no_existing_hotfix_branches
      hotfix_branches = git_local_branches.find_all do |b|
        b =~ /^#{@prefix}/
      end
      unless hotfix_branches.size.zero?
        abort "There is an existing hotfix branch (#{hotfix_branches[0].sub(/^#{@prefix}/, '')}). Finish that one first."
      end
    end

    def start
      @base ||= @master_branch
      require_version_arg
      require_base_is_on_master
      require_no_existing_hotfix_branches

      # sanity checks
      require_clean_working_tree
      require_branch_absent(@branch)
      require_tag_absent("#{@version_prefix}#{@version}")
      if @options.fetch
        run("git fetch -q #{@origin} #{@master_branch}")
      end
      if git_remote_branches.include?("#{@origin}/#{@master_branch}")
        require_branches_equal(@master_branch, "#{@origin}/#{@master_branch}")
      end

      # create branch
      run("git checkout -b #{@branch} #{@base}")

      puts
      puts "Summary of actions:"
      puts "- A new branch '#{@branch}' was created, based on '#{@base}'"
      puts "- You are now on branch '#{@branch}'"
      puts
      puts "Follow-up actions:"
      puts "- Bump the version number now!"
      puts "- Start committing your hot fixes"
      puts "- When done, run:"
      puts
      puts "     git flow hotfix finish '#{@version}'"
      puts
    end

    def finish
      require_version_arg

      # handle flags that imply other flags
      @options.sign = true if @options.signingkey

      # sanity checks
      require_branch(@branch)
      require_clean_working_tree
      if @options.fetch
        abort "Could not fetch #{@master_branch} from #{@origin}." unless
          run_successful("git fetch -q #{@origin} #{@master_branch}")
        abort "Could not fetch #{@develop_branch} from #{@origin}." unless
          run_succssful("git fetch -q #{@origin} #{@develop_branch}")
      end
      if git_remote_branches.include?("#{@origin}/#{@master_branch}")
        require_branches_equal(@master_branch, "#{@origin}/#{@master_branch}")
      end
      if git_remote_branches.include?("#{@origin}/#{@develop_branch}")
        require_branches_equal(@develop_branch, "#{@origin}/#{@develop_branch}")
      end

      # try to merge into master
      # in case a previous attempt to finish this hotfix branch has failed,
      # but the merge into master was successful, we skip it now
      unless git_is_branch_merged_into(@branch, @master_branch)
        abort "Could not check out #{@master_branch}." unless
          run_successful("git checkout #{@master_branch}")
        abort "There were merge conflicts." unless
          run_successful("git merge --no-ff #{@branch}")
        # TODO: What do we do now?
      end

      if @options.tag
        # try to tag the hotfix
        # in case a previous attempt to finish this hotfix branch has failed,
        # but the tag was set successful, we skip it now
        tagname = @version_prefix + @version
        unless git_tag_exists(tagname)
          opts = ["-a"]
          opts << "-s" if @options.sign
          opts << "-u '#{@options.signingkey}'" if @options.signingkey
          message = @options.message
          message = "Tag #{tagname}" if message.nil? or message.empty?
          opts << "-m '#{message}'"
          abort "Tagging failed. Please run finish again to retry." unless
            run_successful("git tag #{opts.join(' ')} #{tagname}")
        end
      end

      # try to merge into develop
      # in case a previous attempt to finish this hotfix branch has failed,
      # but the merge into develop was successful, we skip it now
      unless git_is_branch_merged_into(@branch, @develop_branch)
        abort "Could not check out #{@develop_branch}." unless
          run_successful("git checkout #{@develop_branch}")

        # TODO: Actually, accounting for 'git describe' pays, so we should
        # ideally git merge --no-ff $tagname here, instead!
        abort "There were merge conflicts." unless
          run_successful("git merge --no-ff #{@branch}")
        # TODO: What do we do now?
      end

      # delete branch
      unless @options.keep
        run("git branch -d #{@branch}")
      end

      if @options.push
        abort "Could not push to #{@develop_branch} from #{@origin}." unless
          run_successful("git push #{@origin} #{@develop_branch}")
        abort "Could not push to #{@master_branch} from #{@origin}." unless
          run_successful("git push #{@origin} #{@master_branch}")
        if @options.tag
          abort "Could not push tags to #{@origin}." unless
            run_successful("git push --tags #{@origin}")
        end
      end

      puts
      puts "Summary of actions:"
      if @options.fetch
        puts "- Latest objects have been fetched from '#{@origin}'"
      end
      puts "- Hotfix branch has been merged into '#{@master_branch}'"
      if @options.tag
        puts "- The hotfix was tagged '#{@version_prefix}#{@version}'"
      end
      puts "- Hotfix branch has been back-merged into '#{@develop_branch}'"
      if @options.keep
        puts "- Hotfix branch '#{@branch}' is still available"
      else
        puts "- Hotfix branch '#{@branch}' has been deleted"
      end
      if @options.push
        puts "- '#{@develop_branch}', '#{@master_branch}' and tags have been pushed to '#{@origin}'"
      end
      puts
    end
  end
end
