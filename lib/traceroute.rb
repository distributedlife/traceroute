class Traceroute
  VERSION = Gem.loaded_specs['traceroute'].version.to_s
  class Railtie < ::Rails::Railtie
    rake_tasks do
      load File.join(File.dirname(__FILE__), 'tasks/traceroute.rake')
    end
  end

  def initialize(app)
    @app = app
    load_ignored_regex!
  end

  def load_everything!
    @app.eager_load!
    ::Rails::InfoController rescue NameError
    ::Rails::WelcomeController rescue NameError
    ::Rails::MailersController rescue NameError
    @app.reload_routes!

    Rails::Engine.subclasses.each(&:eager_load!)
  end

  def defined_action_methods
    ActionController::Base.descendants.map do |controller|
      controller.action_methods.reject {|a| (a =~ /\A(_conditional)?_callback_/) || (a == '_layout_from_proc')}.map do |action|
        "#{controller.controller_path}##{action}"
      end
    end.flatten.reject {|r| @ignored_unreachable_actions.any? { |m| r.match(m) } }
  end

  def routed_actions
    routes.map do |r|
      if r.requirements[:controller].blank? && r.requirements[:action].blank? && (r.path == '/:controller(/:action(/:id(.:format)))')
        %Q["#{r.path}"  This is a legacy wild controller route that's not recommended for RESTful applications.]
      else
        "#{r.requirements[:controller]}##{r.requirements[:action]}"
      end
    end.flatten.reject {|r| @ignored_unused_routes.any? { |m| r.match(m) } }
  end

  private
  def filenames
    [".traceroute.yaml", ".traceroute.yml", ".traceroute"].select { |filename|
      File.exists? filename
    }.select { |filename|
      YAML.load_file(filename)
    }
  end

  def at_least_one_file_exists?
    return !filenames.empty?
  end

  def ignore_config
    filenames.each do |filename|
      return YAML.load_file(filename)
    end
  end

  def load_ignored_regex!
    @ignored_unreachable_actions = [/^rails\//]
    @ignored_unused_routes = [/^rails\//]

    return unless at_least_one_file_exists?

    if ignore_config.has_key? 'ignore_unreachable_actions'
      unless ignore_config['ignore_unreachable_actions'].nil?
        ignore_config['ignore_unreachable_actions'].each do |ignored_action|
          @ignored_unreachable_actions << Regexp.new(ignored_action)
        end
      end
    end

    if ignore_config.has_key? 'ignore_unused_routes'
      unless ignore_config['ignore_unused_routes'].nil?
        ignore_config['ignore_unused_routes'].each do |ignored_action|
          @ignored_unused_routes << Regexp.new(ignored_action)
        end
      end
    end
  end

  def routes
    routes = @app.routes.routes.reject {|r| r.name.nil? && r.requirements.blank?}

    routes.reject! {|r| r.app.is_a?(ActionDispatch::Routing::Mapper::Constraints) && r.app.app.respond_to?(:call)}

    if @app.config.respond_to?(:assets)
      exclusion_regexp = %r{^#{@app.config.assets.prefix}}

      routes.reject! do |route|
        path = (defined?(ActionDispatch::Journey::Route) || defined?(Journey::Route)) ? route.path.spec.to_s : route.path
        path =~ exclusion_regexp
      end
    end
    routes
  end
end
