#
# Rack::AutoCRUD - AutoCRUD Middleware for Rack
#
# Copyright (C) 2012 Tim Hentenaar. All Rights Reserved.
#
# Licensed under the Simplified BSD License.
# See the LICENSE file for details.
#
# This Rack middleware automatically generates Sinatra
# endpoints (descended from Sinatra::Base) to handle
# basic CRUD operations on defined models.
#

require 'sinatra/base'
require 'json'

module Rack
  class AutoCRUD
    def initialize(app,options={})
      @app                = app
      @model_namespace    = options[:model_namespace]
      @endpoint_namespace = options[:endpoint_namespace]
      @includes           = options[:includes]     || []
      @sinatra_opts       = options[:sinatra_opts] || {}
      @endpoint_mod       = nil
      @model_mod          = nil
    end

    def call(env)
      dup._call(env) # For thread safety...
    end

    def _call(env)
      model_klass        = nil
      endpoint_klass     = nil
      verb,endpoint,*uri = env['PATH_INFO'].split('/')
      verb               = env['REQUEST_METHOD'].downcase

      # If this is to '/' pass it on
      return @app.call(env) if endpoint.nil?

      # Enumerate through all defined classes, checking for the
      # model / endpoint
      ObjectSpace.each_object(Class) { |klass|
        kname = String(klass.name).downcase
        mname = String(@model_namespace    + '::' + endpoint).downcase
        ename = String(@endpoint_namespace + '::' + endpoint).downcase

        model_klass    = klass if kname == mname
        endpoint_klass = klass if kname == ename
      }

      # Lazily locate the model namespace module (if we haven't already)
      if @model_mod.nil?
        ObjectSpace.each_object(Module) { |klass|
          if String(klass.name).downcase == @model_namespace.downcase
            @model_mod = klass
          end
        }
      end

      # Lazily locate the endpoint namespace module (if we haven't
      # already)
      if endpoint_klass.nil? && @endpoint_mod.nil?
        ObjectSpace.each_object(Module) { |klass|
          if String(klass.name).downcase == @endpoint_namespace.downcase
            @endpoint_mod = klass
          end
        }
      end

      # Make sure we copy the :EXPOSE constant if it's defined upstream
      if !model_klass.nil? && !model_klass.const_defined?(:EXPOSE) &&
         @model_mod.const_defined?(:EXPOSE)
        model_klass.const_set(:EXPOSE,@model_mod.const_get(:EXPOSE))
      end

      # Make sure we copy the :COLLECTABLE constant if it's defined
      # upstream
      if !model_klass.nil? && !model_klass.const_defined?(:COLLECTABLE) &&
         @model_mod.const_defined?(:COLLECTABLE)
        model_klass.const_set(:COLLECTABLE,
                              @model_mod.const_get(:COLLECTABLE))
      end

      # Now, if we've got something, do our magic.
      if !model_klass.nil? && (
        !model_klass.const_defined?(:EXPOSE) ||
        model_klass.const_get(:EXPOSE)
      )
        # If we don't have an endpoint class, make one
        if endpoint_klass.nil?
          endpoint_klass = Class.new(Sinatra::Base)
          @endpoint_mod.const_set(endpoint.capitalize,endpoint_klass)
        end

        # Add in any specified helpers
        @includes.each { |inc|
          endpoint_klass.send(:include,inc)
        } unless @includes.nil?

        # Set any Sinatra options
        @sinatra_opts.each { |sopt,val|
          endpoint_klass.send(:set,sopt,val)
        }

        # Patch in the routes
        endpoint_klass.class_exec(model_klass,endpoint) { |model,ep|
          def set_request_body(new_body,content_type='text/json')
            env['rack.input']     = StringIO.new(new_body)
            env['CONTENT_LENGTH'] = new_body.length
            env['CONTENT_TYPE']   = content_type
            return nil
          end

          get '/count' do
            halt [
              403,
              '{ "error": "Access Denied" }'
            ] unless model_klass.const_defined?(:COLLECTABLE) &&
                     model.const_get(:COLLECTABLE)

            # Return the count
            { :count => model.all.count }.to_json
          end

          get '/' do
            halt [
              403,
              '{ "error": "Access Denied" }'
            ] unless model_klass.const_defined?(:COLLECTABLE) &&
                     model.const_get(:COLLECTABLE)

            # Call the pre-create hook
            if self.respond_to?(:pre_collect)
              ret = pre_collect(model,request,params)
              return ret unless ret.nil?
            end

            # Get the collection
            collection = model.all

            # Call the post-collect hook
            if self.respond_to?(:post_collect)
              ret = post_collect(model,request,collection)
              return ret unless ret.nil?
            end

            collection.to_json({},request.env)
          end

          post '/' do
            # Call the pre-create hook
            if self.respond_to?(:pre_create)
              ret = pre_create(model,request,params)
              return ret unless ret.nil?
            end

            # Rewind the body
            request.body.rewind if request.body.respond_to?(:rewind)

            # Attempt to create the model object
            obj = nil
            begin
              obj = model.create(JSON.parse(request.body.read))
              halt [
                402,
                '{ "error": "Failed to save ' + ep + '" }'
              ] unless obj && obj.saved?
            rescue JSON::ParserError
              halt [
                400,
                {
                  'error' => 'Invalid JSON in request body.',
                  'details' => $!
                }.to_json
              ]
            end

            # Call the post-create hook
            if self.respond_to?(:post_create)
              ret = post_create(model,request,obj)
              return ret unless ret.nil?
            end

            [ 201, { 'id' => obj.id.to_i }.to_json ]
          end

          get '/:id' do
            # Call the pre-retrieve hook
            if self.respond_to?(:pre_retrieve)
              ret = pre_retrieve(model,request,params)
              return ret unless ret.nil?
            end

            obj = model.get(params[:id])

            # Call the post-retrieve hook
            if self.respond_to?(:post_retrieve)
              ret = post_retrieve(model,request,obj)
              return ret unless ret.nil?
            end

            obj.to_json({},request.env)
          end

          put '/:id' do
            # Call the pre-update hook
            if self.respond_to?(:pre_update)
              ret = pre_update(model,request,params)
              return ret unless ret.nil?
            end

            # Rewind the body
            request.body.rewind if request.body.respond_to?(:rewind)

            # Attempt to update the model
            begin
              saved = model.get(params[:id]).update(
                JSON.parse(request.body.read)
              )
              halt [ 402, '{ "error": "Access Denied" }' ] unless saved
            rescue JSON::ParserError
              halt [
                400,
                {
                  'error' => 'Invalid JSON in request body.',
                  'details' => $!
                }.to_json
              ]
            end

            # Call the post-update hook
            if self.respond_to?(:post_update)
              ret = post_update(model,request,params)
              return ret unless ret.nil?
            end

            [ 201, '{ "status": "ok" }' ]
          end

          delete '/:id' do
            # Call the pre-destroy hook
            if self.respond_to?(:pre_destroy)
              ret = pre_destroy(model,request,params)
              return ret unless ret.nil?
            end

            obj = model.get(params[:id])
            return [
              402,
              '{ "error": "Failed to delete ' + ep + '" }'
            ] unless obj && obj.destroy

            # Call the post-destroy hook
            if self.respond_to?(:post_destroy)
              ret = post_destroy(model,request,obj)
              return ret unless ret.nil?
            end

            [ 204 ]
          end
        }

        # Now, save PATH_INFO, reset it, and call our endpoint
        old_path_info       = env['PATH_INFO']
        env['PATH_INFO']    = '/' + uri.join('/')
        env['CONTENT_TYPE'] = 'text/json'
        response            = endpoint_klass.call(env)

        # Restore PATH_INFO
        env['PATH_INFO'] = old_path_info
        return response
      end

      # Otherwise, pass the request down the chain...
      @app.call(env)
    end
  end
end

# vi:set ts=2 sw=2 expandtab sta:
