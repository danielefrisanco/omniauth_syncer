require 'rails/engine'

module OmniauthSyncer
  class Engine < ::Rails::Engine
    # Allows the host application to use OmniauthSyncer configurations
    isolate_namespace OmniauthSyncer

    # This initializer runs before all other application initializers.
    # It ensures that our configuration block is loaded early.
    initializer 'omniauth_syncer.configure_defaults' do
      # Load your configuration settings here if needed,
      # but typically, we rely on the host app's initializer.
    end

    # Optionally, you can include logic to automatically integrate
    # the SyncService into the host app's controller.
    initializer 'omniauth_syncer.controller_mixin' do
      ActiveSupport.on_load(:action_controller_base) do
        # This is where you would define a helper method
        # that the user can call in their OmniAuth controller:
        # include OmniauthSyncer::ControllerHelpers
      end
    end
  end
end
