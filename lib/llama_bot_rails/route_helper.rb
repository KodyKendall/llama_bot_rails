module LlamaBotRails
  module RouteHelper
    # Extracts the description from YARD comments
    def self.extract_yard_description(comment_text)
      comment_text.lines.map { |l| l.sub(/^# ?/, '') }
                  .take_while { |l| !l.strip.start_with?('@') }
                  .join(' ').strip
    end

    # Extracts a specific YARD tag from comments
    def self.extract_yard_tag(comment_text, tag)
      if match = comment_text.match(/@#{tag} (.+)/)
        match[1].strip
      end
    end

    # Main method: returns XML string of formatted routes for allowed_routes
    def self.formatted_routes_xml(allowed_routes)
      xml_routes = ""
      allowed_routes.each do |route_str|
        controller, action = route_str.split('#')
        matching_routes = Rails.application.routes.routes.select do |r|
          r.defaults[:controller] == controller && r.defaults[:action] == action
        end

        matching_routes.each do |r|
          verb = r.verb.to_s.gsub(/[$^]/, '') # Handles both Regexp and String
          path = r.path.spec.to_s
          path_params = path.scan(/:\w+/).map { |p| p[1..-1] } # e.g. ["id"]

          # Extract controller class and strong parameters
          controller_class = "#{controller.camelize}Controller".safe_constantize
          strong_params = []
          yard_metadata = {}

          if controller_class
            # Extract YARD documentation for the action
            begin
              method_obj = controller_class.instance_method(action.to_sym)
              source_location = method_obj.source_location
              if source_location
                file_path, line_number = source_location
                file_lines = File.readlines(file_path)
                # Look for YARD comments above the method
                comment_lines = []
                current_line = line_number - 2 # Start above the method definition
                while current_line >= 0 && file_lines[current_line].strip.start_with?('#')
                  comment_lines.unshift(file_lines[current_line].strip)
                  current_line -= 1
                end
                # Parse YARD tags
                comment_text = comment_lines.join("\n")
                yard_metadata[:description] = extract_yard_description(comment_text)
                yard_metadata[:tool_description] = extract_yard_tag(comment_text, 'tool_description')
                yard_metadata[:example] = extract_yard_tag(comment_text, 'example')
                yard_metadata[:params] = extract_yard_tag(comment_text, 'params')
              end
            rescue => e
              # Silently continue if YARD parsing fails
            end
            # Look for the strong parameter method (e.g., page_params, user_params, etc.)
            param_method = "#{controller.singularize}_params"
            if controller_class.private_method_defined?(param_method.to_sym)
              source_location = controller_class.instance_method(param_method.to_sym).source_location
              if source_location
                file_path, line_number = source_location
                file_lines = File.readlines(file_path)
                method_lines = []
                current_line = line_number - 1
                while current_line < file_lines.length
                  line = file_lines[current_line].strip
                  method_lines << line
                  break if line.include?('end') && !line.include?('permit')
                  current_line += 1
                end
                method_source = method_lines.join(' ')
                if match = method_source.match(/\.permit\((.*?)\)/)
                  permit_content = match[1]
                  strong_params = permit_content.scan(/:(\w+)/).flatten
                end
              end
            end
            # Also check for any additional params the action might accept
            additional_params = []
            case action
            when 'update', 'create'
              if controller == 'pages' && action == 'update'
                additional_params << 'message'
              end
            end
            all_params = (path_params + strong_params + additional_params).uniq
          else
            all_params = path_params
          end

          xml = <<~XML
            <route>
              <name>#{route_str}</name>
              <verb>#{verb}</verb>
              <path>#{path}</path>
              <path_params>#{path_params.join(', ')}</path_params>
              <accepted_params>#{all_params.join(', ')}</accepted_params>
              <strong_params>#{strong_params.join(', ')}</strong_params>
              <description>#{yard_metadata[:description]}</description>
              <tool_description>#{yard_metadata[:tool_description]}</tool_description>
              <example>#{yard_metadata[:example]}</example>
              <params>#{yard_metadata[:params]}</params>
            </route>
          XML

          xml_routes += xml
        end
      end
      xml_routes
    end
  end
end