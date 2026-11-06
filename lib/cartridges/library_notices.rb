# frozen_string_literal: true

require "adwaita"
require_relative "shared"

module Cartridges
  # LibraryNotices builds the four status pages the library overlays show
  # when there is nothing to display: an empty shown library (with an Import
  # button), an empty hidden library, and a "no results" page for each when a
  # search or filter matches nothing.
  #
  # Ported from the four standalone Adw.StatusPage blocks at the top of
  # data/gtk/window.blp.
  class LibraryNotices
    def no_results
      @no_results ||= status_page("system-search-symbolic", "No Games Found", "Try a different search")
    end

    def hidden_no_results
      @hidden_no_results ||= status_page("system-search-symbolic", "No Games Found", "Try a different search")
    end

    def empty
      @empty ||= status_page(nil, "No Games", "Use the + button to add games").tap do |page|
        page.icon_name = "#{Shared::APP_ID}-symbolic"
        page.child = import_button
      end
    end

    def hidden_empty
      @hidden_empty ||= status_page("view-conceal-symbolic", "No Hidden Games", "Games you hide will appear here")
    end

    private

      def status_page(icon_name, title, description)
        Adwaita::StatusPage.new.tap do |page|
          page.icon_name = icon_name if icon_name
          page.title = title
          page.description = description
          page.vexpand = true
          page.valign = :center
        end
      end

      def import_button
        @import_button ||= Gtk::Button.new.tap do |btn|
          btn.label = "Import"
          btn.halign = :center
          btn.action_name = "app.import"
          btn.add_css_class("pill")
          btn.add_css_class("suggested-action")
        end
      end
  end
end
