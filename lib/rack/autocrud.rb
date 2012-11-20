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
      @includes           = options[:includes]
      @endpoint_mod       = nil
      @model_mod          = nil
    end

    def call(env)
      dup._call(env) # For thread safety...
    end

    def _call(env)
      model_klass        = nil
      endpoint_klass     = nil
      verb,endpoint,*uri = env['REQUEST_URI'].split('/')
      verb               = env['REQUEST_METHOD'].downcase

      # If this is to '/' pass it on
      return @app.call(env) if endpoint.nil?

      # Enumerate through all defined classes, checking for the model / endpoint
      ObjectSpace.each_object(Class) { |klass|
        model_klass    = klass if String(klass.name).downcase == String(@model_namespace    + '::' + endpoint).downcase
        endpoint_klass = klass if String(klass.name).downcase == String(@endpoint_namespace + '::' + endpoint).downcase
      }

      # Lazily locate the model namespace module (if we haven't already)
      if @model_mod.nil?
        ObjectSpace.each_object(Module) { |klass|
          @model_mod = klass if String(klass.name).downcase == @model_namespace.downcase
        }
      end

      # Lazily locate the endpoint namespace module (if we haven't already)
      if endpoint_klass.nil? && @endpoint_mod.nil?
        ObjectSpace.each_object(Module) { |klass|
          @endpoint_mod = klass if String(klass.name).downcase == @endpoint_namespace.downcase
        }
      end

      # Make sure we copy the :EXPOSE constant if it's defined upstream
      if !model_klass.const_defined?(:EXPOSE) && @model_mod.const_defined?(:EXPOSE)
        model_klass.const_set(:EXPOSE,@model_mod.const_get(:EXPOSE))
      end

      # Now, if we've got something, do our magic.
      if !model_klass.nil? && (!model_klass.const_defined?(:EXPOSE) || model_klass.const_get(:EXPOSE))
        # If we don't have an endpoint class, make one
        if endpoint_klass.nil?
          endpoint_klass = Class.new(Sinatra::Base)
          @endpoint_mod.const_set(endpoint.capitalize,endpoint_klass)
        end

        # Add in any specified helpers
        @includes.each { |inc| endpoint_klass.send(:include,inc) } unless @includes.nil?

        # Patch in the routes
        endpoint_klass.class_exec(model_klass,endpoint,env) { |model,endpoint,env|
          def set_request_body(new_body,content_type='text/json')
            env['rack.input']     = StringIO.new(new_body)
            env['CONTENT_LENGTH'] = new_body.length
            env['CONTENT_TYPE']   = content_type
            return nil
          end

          get '/' do
            halt [ 403, '{ "error": "Access Denied" }' ]
          end

          post '/' do
            # Call the pre-create hook
            if self.respond_to?(:pre_create)
              ret = pre_create(env,request,params)
              return ret unless ret.nil?
            end

            # Rewind the body
            request.body.rewind if request.body.respond_to?(:rewind)

            # Attempt to create the model object
            obj = nil
            begin
              obj = model.new(JSON.parse(request.body.read))
              halt [ 402, '{ "error": "Failed to save ' + endpoint + '" }' ] unless obj && obj.saved?
            rescue JSON::ParserError
              halt [ 400, { 'error' => 'Invalid JSON in request body.', 'details' => $! }.to_json ]
            end

            # Call the post-create hook
            if self.respond_to?(:post_create)
              ret = post_create(env,request,obj)
              return ret unless ret.nil?
            end

            [ 201, { 'id' => obj.id.to_i }.to_json ]
          end

          get '/:id' do
            # Call the pre-retrieve hook
            if self.respond_to?(:pre_retrieve)
              ret = pre_retrieve(env,request,params)
              return ret unless ret.nil?
            end

            obj = model.get(params[:id])

            # Call the post-retrieve hook
            if self.respond_to?(:post_retrieve)
              ret = post_retrieve(env,request,obj)
              return ret unless ret.nil?
            end

            obj.to_json
          end

          put '/:id' do
            # Call the pre-update hook
            if self.respond_to?(:pre_update)
              ret = pre_update(env,request,params)
              return ret unless ret.nil?
            end

            # Rewind the body
            request.body.rewind if request.body.respond_to?(:rewind)

            # Attempt to update the model
            begin
              saved = model.update(JSON.parse(request.body.read).merge(:id => params[:id]))
              halt [ 402, '{ "error": "Access Denied" }' ] unless saved
            rescue JSON::ParserError
              halt [ 400, { 'error' => 'Invalid JSON in request body.', 'details' => $! }.to_json ]
            end

            # Call the post-update hook
            if self.respond_to?(:post_update)
              ret = post_update(env,request,params)
              return ret unless ret.nil?
            end

            [ 201, '{ "status": "ok" }' ]
          end

          delete '/:id' do
            # Call the pre-destroy hook
            if self.respond_to?(:pre_destroy)
              ret = pre_destroy(env,request,params)
              return ret unless ret.nil?
            end

            obj = model.get(params[:id])
            obj.destroy! if obj

            # Call the post-destroy hook
            if self.respond_to?(:post_destroy)
              ret = post_destroy(env,request,obj)
              return ret unless ret.nil?
            end

            [ 204 ]
          end
        }

        # Now, call the endpoint class (assuming it will return a response)
        env['PATH_INFO'] = '/' + uri.join('/')
        return endpoint_klass.call(env)
      end

      # Otherwise, pass the request down the chain...
      @app.call(env)
    end
  end
end

# vi:set ts=2 sw=2 expandtab sta:
