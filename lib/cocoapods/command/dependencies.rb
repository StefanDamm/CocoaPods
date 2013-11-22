module Pod
  class Command
    class Dependencies < Command
      self.summary = 'Show dependency tree'
      
      # @return [Hash<String => Set>] A cache that keeps tracks of the sets
      #         loaded by the resolution process.
      #
      # @note   Sets store the resolved dependencies and return the highest
      #         available specification found in the sources. This is done
      #         globally and not per target definition because there can be just
      #         one Pod installation, so different version of the same Pods for
      #         target definitions are not allowed.
      #
      attr_accessor :cached_sets
      
      # @return [Source::Aggregate] A cache of the sources needed to find the
      #         podspecs.
      #
      # @note   The sources are cached because frequently accessed by the
      #         resolver and loading them requires disk activity.
      #
      attr_accessor :cached_sources
      
      # @return [Hash<String => Specification>] The loaded specifications grouped
      #         by name.
      #
      attr_accessor :cached_specs
      
      # @return [Sandbox] the Sandbox used by the resolver to find external
      #         dependencies.
      #
      attr_reader :sandbox
      
      # @return [Hash<String => Array>] List of pods that are dependend on the pod
      #
      attr_accessor :reverse_dependencies

      self.description = <<-DESC
        Shows a tree of pod dependencies. Where the child nodes have dependencies on the parent. Can be used to see what pods are effected when updating a pod.
      DESC

      def self.options
        [[
          "--html", "Print output as html page"
        ]].concat(super)
      end

      def initialize(argv)
        @dependency_name = argv.shift_argument
        @html  = argv.flag?('html')
        
        @cached_sources  = SourcesManager.aggregate
        @cached_sets     = {}
        @cached_specs    = {}
        @sandbox = config.sandbox
        @reverse_dependencies = {}
        super
      end
      
      def lookup_dependencies(dependent_spec, dependencies, target_definition)       
        dependencies.each do |dependency|        
          reverse_dependencies[dependency.name] = [] unless reverse_dependencies.include?(dependency.name)
          
          next if reverse_dependencies[dependency.name].include?(dependent_spec.name)
          
          reverse_dependencies[dependency.name] << dependent_spec.name

          set = find_cached_set(dependency)

          spec = set.specification.subspec_by_name(dependency.name)
          cached_specs[spec.name] = spec

          spec_dependencies = spec.all_dependencies(target_definition.platform)
          lookup_dependencies(spec, spec_dependencies, target_definition)
        end
        
        
      end


      def run
        verify_podfile_exists!
        verify_lockfile_exists!
        
        print_html_header if @html
        
        sets = SourcesManager.all_sets
        
        target_definitions = config.podfile.target_definition_list
        
        target_definitions.each do |target|
          UI.section "Resolving dependencies for target `#{target.name}' (#{target.platform})" do
            sets.each do |set|
              next unless !@dependency_name.nil? and set.name.include? @dependency_name
              begin
                spec = set.specification.subspec_by_name(set.name)
                dependencies = spec.all_dependencies(target.platform)
                lookup_dependencies(spec, dependencies, target)
              rescue Pod::StandardError => e
                $stderr.puts e
              end
            end
          end
        end
        
        print_recursive reverse_dependencies.keys,0
        
        UI.puts "</body></html>" if @html
      end
      
      def print_recursive pods,level
        return unless pods
        
        if @html
          if level == 0
            UI.puts "<ul>" 
          else
            UI.puts "<ul class='collapsibleList'>" 
          end
        end
        
        pods.each do |pod|        
          if @html
            UI.puts "<li>#{pod}"
          else
            lvl = ''
            level.times {lvl=lvl+"   "}
            UI.puts "#{lvl}#{pod}"
          end
          print_recursive reverse_dependencies[pod],level+1
          
          UI.puts "</li>" if @html
        end
        
         UI.puts "</ul>" if @html
      end
      
      
      # Loads or returns a previously initialized for the Pod of the given
      # dependency.
      #
      # @param  [Dependency] dependency
      #         the dependency for which the set is needed.
      #
      # @return [Set] the cached set for a given dependency.
      #
      def find_cached_set(dependency)
        name = dependency.root_name
        unless cached_sets[name]
          if dependency.external_source
            spec = sandbox.specification(dependency.root_name)
            unless spec
              raise StandardError, "[Bug] Unable to find the specification for `#{dependency}`."
            end
            set = Specification::Set::External.new(spec)
          else
            set = cached_sources.search(dependency)
          end
          cached_sets[name] = set
          unless set
            raise Informative, "Unable to find a specification for `#{dependency}`."
          end
        end
        cached_sets[name]
      end
      
      def print_html_header
        UI.puts "<html><head>
        <script type='text/javascript'><!--
        /*

        CollapsibleLists.js

        An object allowing lists to dynamically expand and collapse

        Created by Stephen Morley - http://code.stephenmorley.org/ - and released under
        the terms of the CC0 1.0 Universal legal code:

        http://creativecommons.org/publicdomain/zero/1.0/legalcode

        */

        // create the CollapsibleLists object
        var CollapsibleLists =
            new function(){

              /* Makes all lists with the class 'collapsibleList' collapsible. The
               * parameter is:
               *
               * doNotRecurse - true if sub-lists should not be made collapsible
               */
              this.apply = function(doNotRecurse){

                // loop over the unordered lists
                var uls = document.getElementsByTagName('ul');
                for (var index = 0; index < uls.length; index ++){

                  // check whether this list should be made collapsible
                  if (uls[index].className.match(/(^| )collapsibleList( |$)/)){

                    // make this list collapsible
                    this.applyTo(uls[index], true);

                    // check whether sub-lists should also be made collapsible
                    if (!doNotRecurse){

                      // add the collapsibleList class to the sub-lists
                      var subUls = uls[index].getElementsByTagName('ul');
                      for (var subIndex = 0; subIndex < subUls.length; subIndex ++){
                        subUls[subIndex].className += ' collapsibleList';
                      }

                    }

                  }

                }

              };

              /* Makes the specified list collapsible. The parameters are:
               *
               * node         - the list element
               * doNotRecurse - true if sub-lists should not be made collapsible
               */
              this.applyTo = function(node, doNotRecurse){

                // loop over the list items within this node
                var lis = node.getElementsByTagName('li');
                for (var index = 0; index < lis.length; index ++){

                  // check whether this list item should be collapsible
                  if (!doNotRecurse || node == lis[index].parentNode){

                    // prevent text from being selected unintentionally
                    if (lis[index].addEventListener){
                      lis[index].addEventListener(
                          'mousedown', function (e){ e.preventDefault(); }, false);
                    }else{
                      lis[index].attachEvent(
                          'onselectstart', function(){ event.returnValue = false; });
                    }

                    // add the click listener
                    if (lis[index].addEventListener){
                      lis[index].addEventListener(
                          'click', createClickListener(lis[index]), false);
                    }else{
                      lis[index].attachEvent(
                          'onclick', createClickListener(lis[index]));
                    }

                    // close the unordered lists within this list item
                    toggle(lis[index]);

                  }

                }

              };

              /* Returns a function that toggles the display status of any unordered
               * list elements within the specified node. The parameter is:
               *
               * node - the node containing the unordered list elements
               */
              function createClickListener(node){

                // return the function
                return function(e){

                  // ensure the event object is defined
                  if (!e) e = window.event;

                  // find the list item containing the target of the event
                  var li = (e.target ? e.target : e.srcElement);
                  while (li.nodeName != 'LI') li = li.parentNode;

                  // toggle the state of the node if it was the target of the event
                  if (li == node) toggle(node);

                };

              }

              /* Opens or closes the unordered list elements directly within the
               * specified node. The parameter is:
               *
               * node - the node containing the unordered list elements
               */
              function toggle(node){

                // determine whether to open or close the unordered lists
                var open = node.className.match(/(^| )collapsibleListClosed( |$)/);

                // loop over the unordered list elements with the node
                var uls = node.getElementsByTagName('ul');
                for (var index = 0; index < uls.length; index ++){

                  // find the parent list item of this unordered list
                  var li = uls[index];
                  while (li.nodeName != 'LI') li = li.parentNode;

                  // style the unordered list if it is directly within this node
                  if (li == node) uls[index].style.display = (open ? 'block' : 'none');

                }

                // remove the current class from the node
                node.className =
                    node.className.replace(
                        /(^| )collapsibleList(Open|Closed)( |$)/, '');

                // if the node contains unordered lists, set its class
                if (uls.length > 0){
                  node.className += ' collapsibleList' + (open ? 'Open' : 'Closed');
                }

              }

            }();


            CollapsibleLists.apply();
        -->
        </script>
        <style type='text/css'>
        .collapsibleList li{
          list-style-type: square
          cursor:auto;
        }

        li.collapsibleListOpen{
          list-style-type: circle;
          cursor:pointer;
        }

        li.collapsibleListClosed{
          list-style-type: disc;
          cursor:pointer;
        }
        </style>
        </head><body onLoad='CollapsibleLists.apply();'>"
      end
      
    end
  end
end


