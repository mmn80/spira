module Spira
 module Resource

   ##
   # This module contains all class methods available to a declared Spira::Resource class.
   # {Spira::Resource} contains more information about Spira resources.
   #
   # @see Spira::Resource
   # @see Spira::Resource::InstanceMethods
   # @see Spira::Resource::DSL
    module ClassMethods

      ##
      # A symbol name for the repository this class is currently using.
      attr_reader :repository_name

      ##
      # The current repository for this class
      # 
      # @return [RDF::Repository, nil]
      # @private
      def repository
        name = @repository_name || :default
        Spira.repository(name)
      end

      ##
      # Get the current repository for this class, and raise a
      # Spira::NoRepositoryError if it is nil.
      #
      # @raise  [Spira::NoRepositoryError]
      # @return [RDF::Repository]
      # @private
      def repository_or_fail
        repository || (raise Spira::NoRepositoryError, "#{self} is configured to use :#{@repository_name || 'default'} as a repository, but it has not been set.")
      end

      ##
      # Create a new projection instance of this class for the given URI.  If a
      # class has a base_uri given, and the argument is not an `RDF::URI`, the
      # given identifier will be appended to the base URI.
      #
      # Spira does not have 'find' or 'create' functions.  As RDF identifiers
      # are globally unique, they all simply 'are'.
      #
      # On calling `for`, a new projection is created for the given URI.  The
      # first time access is attempted on a field, the repository will be
      # queried for existing attributes, which will be used for the given URI.
      # Underlying repositories are not accessed at the time of calling `for`.
      # 
      # A class with a base URI may still be projected for any URI, whether or
      # not it uses the given resource class' base URI.
      # 
      # @raise [TypeError] if an RDF type is given in the attributes and one is
      # given in the attributes.  
      # @raise [ArgumentError] if a non-URI is given and the class does not
      # have a base URI.  
      # @overload for(uri, attributes = {})
      #   @param [RDF::URI] uri The URI to create an instance for
      #   @param [Hash{Symbol => Any}] attributes Initial attributes
      # @overload for(identifier, attributes = {})
      #   @param [Any] uri The identifier to append to the base URI for this class
      #   @param [Hash{Symbol => Any}] attributes Initial attributes
      # @overload for(hash, attributes = {})
      #   @param [Hash{Symbol => Any}] hash A hash with a `:identifier` key pointing to an 
      # uri or an identifier as above, and `:context` pointing to a [RDF::Value]
      # to be used as a default context for the object instead of `default_context`
      #   @param [Hash{Symbol => Any}] attributes Initial attributes
      # @yield [self] Executes a given block and calls `#save!`
      # @yieldparam [self] self The newly created instance
      # @return  [Spira::Resource] The newly created instance
      # @see http://rdf.rubyforge.org/RDF/URI.html
      def for(identifier, attributes = {}, &block)
        context = @default_context
        if identifier.is_a?(Hash)
          context = identifier[:context]
          identifier = identifier[:identifier]
        end
        self.project(id_for(identifier), context, attributes, &block)
      end

      ##
      # Create a new instance with the given subject without any modification to
      # the given subject at all.  This method exists to provide an entry point
      # for implementing classes that want to create a more intelligent .for
      # and/or .id_for for their given use cases, such as simple string
      # appending to base URIs or calculated URIs from other representations.
      #
      # @example Using simple string concatentation with base_uri in .for instead of joining delimiters
      #     def for(identifier, attributes = {}, &block)
      #       self.project(RDF::URI(self.base_uri.to_s + identifier.to_s), attributes, &block)
      #     end
      # @param [RDF::URI, RDF::Node] subject
      # @param [Hash{Symbol => Any}] attributes Initial attributes
      # @return [Spira::Resource] the newly created instance
      def project(subject, context, attributes = {}, &block)
        if !self.type.nil? && attributes[:type]
          raise TypeError, "#{self} has an RDF type, #{self.type}, and cannot accept one as an argument."
        end
        self.new(attributes.merge(:_subject => subject, :_context => context), &block)
      end

      ##
      # Alias for #for
      #
      # @see #for
      def [](*args)
        self.for(*args)
      end

      ##
      # Creates a URI or RDF::Node based on a potential base_uri and string,
      # URI, or Node, or Addressable::URI.  If not a URI or Node, the given
      # identifier should be a string representing an absolute URI, or
      # something responding to to_s which can be appended to a base URI, which
      # this class must have.
      #
      # @param  [Any] Identifier
      # @return [RDF::URI, RDF::Node]
      # @raise  [ArgumentError] If this class cannot create an identifier from the given argument
      # @see http://rdf.rubyforge.org/RDF/URI.html
      # @see Spira::Resource.base_uri
      # @see Spira::Resource.for
      def id_for(identifier)
        case
          # Absolute URI's go through unchanged
          when identifier.is_a?(RDF::URI) && identifier.absolute?
            identifier
          # We don't have a base URI to join this fragment with, so go ahead and instantiate it as-is.
          when identifier.is_a?(RDF::URI) && self.base_uri.nil?
            identifier
          # Blank nodes go through unchanged
          when identifier.respond_to?(:node?) && identifier.node?
            identifier
          # Anything that can be an RDF::URI, we re-run this case statement
          # on it for the fragment logic above.
          when identifier.respond_to?(:to_uri) && !identifier.is_a?(RDF::URI)
            id_for(identifier.to_uri)
          # see comment with #to_uri above, this might be a fragment
          when identifier.is_a?(Addressable::URI)
            id_for(RDF::URI.intern(identifier))
          # This is a #to_s or a URI fragment with a base uri.  We'll treat them the same.
          # FIXME: when #/ makes it into RDF.rb proper, this can all be wrapped
          # into the one case statement above.
          else
            uri = identifier.is_a?(RDF::URI) ? identifier : RDF::URI.intern(identifier.to_s)
            case
              when uri.absolute?
                uri
              when self.base_uri.nil?
                raise ArgumentError, "Cannot create identifier for #{self} by String without base_uri; an RDF::URI is required" if self.base_uri.nil?
              else
                separator = self.base_uri.to_s[-1,1] =~ /(\/|#)/ ? '' : '/'
                RDF::URI.intern(self.base_uri.to_s + separator + identifier.to_s)
            end
        end
      end


      ##
      # The number of URIs projectable as a given class in the repository.
      # This method is only valid for classes which declare a `type` with the
      # `type` method in the DSL.
      #
      # @raise  [Spira::NoTypeError] if the resource class does not have an RDF type declared
      # @return [Integer] the count
      # @see Spira::Resource::DSL
      def count
        raise Spira::NoTypeError, "Cannot count a #{self} without a reference type URI." if @type.nil?
        repository.query(:predicate => RDF.type, :object => @type, :context => @default_context).subjects.count
      end

      ##
      # A cache of iterated instances of this projection
      #
      # @return [RDF::Util::Cache]
      # @private
      def cache
        @cache ||= RDF::Util::Cache.new
      end

      ##
      # Clear the iteration cache
      # 
      # @return [void]
      def reload
        @cache = nil
      end

      ##
      # Enumerate over all resources projectable as this class.  This method is
      # only valid for classes which declare a `type` with the `type` method in
      # the DSL.
      #
      # @raise  [Spira::NoTypeError] if the resource class does not have an RDF type declared
      # @overload each
      #   @yield [instance] A block to perform for each available projection of this class
      #   @yieldparam [self] instance
      #   @yieldreturn [Void]
      #   @return [Void]
      #
      # @overload each
      #   @return [Enumerator]
      # @see Spira::Resource::DSL
      def each(&block)
        raise Spira::NoTypeError, "Cannot count a #{self} without a reference type URI." if @type.nil?
        case block_given?
          when false
            enum_for(:each)
          else
            repository_or_fail.query(:predicate => RDF.type, :object => @type, :context => @default_context).each_subject do |subject|
              self.cache[subject] ||= self.for(subject)
              block.call(cache[subject])
            end
        end
      end

      ##
      # Returns true if the given property is a has_many property, false otherwise
      #
      # @return [true, false]
      def is_list?(property)
        @lists.has_key?(property)
      end

      ##
      # Handling inheritance
      #
      # @private
      def inherited(child)
        child.instance_eval do
          include Spira::Resource
        end
        # FIXME: This is clearly brittle and ugly.
        [:@base_uri, :@default_vocabulary, :@repository_name, :@type, :@default_context].each do |variable|
          value = instance_variable_get(variable).nil? ? nil : instance_variable_get(variable).dup
          child.instance_variable_set(variable, value)
        end
        [:@properties, :@lists, :@validators].each do |variable|
          if child.instance_variable_get(variable).nil?
            if instance_variable_get(variable).nil?
              child.instance_variable_set(variable, nil)
            else
              child.instance_variable_set(variable, instance_variable_get(variable).dup)
            end
          elsif !(instance_variable_get(variable).nil?)
            child.instance_variable_set(variable, instance_variable_get(variable).dup.merge(child.instance_variable_get(variable)))
          end
        end
      end

      ## 
      # Handling module inclusions
      #
      # @private
      def included(child)
        inherited(child)
      end

      ## 
      # The list of validation functions for this projection
      #
      # @return [Array<Symbol>]
      def validators
        @validators ||= []
      end

    end
  end
end
