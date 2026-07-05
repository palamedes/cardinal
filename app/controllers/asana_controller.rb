# Asana import (card #7). First visit is a connect wizard (PAT walkthrough);
# once connected it's a one-field modal: paste the task URL, get a card.
class AsanaController < ApplicationController
  def new_card
    @board = Board.first!
    redirect_to root_path and return unless turbo_frame_request?
    @connected = Asana.connected?
    @error = params[:error]
    @just_connected = params[:connected]
  end

  def connect
    name = Asana.verify!(params.require(:token))
    Asana.save_token!(params[:token])
    redirect_to asana_new_card_path(connected: name)
  rescue Asana::Error => e
    redirect_to asana_new_card_path(error: e.message)
  end

  def import
    card = Asana.import!(Board.first!, params.require(:url))
    redirect_to card_path(card)
  rescue Asana::Error => e
    redirect_to asana_new_card_path(error: e.message)
  end

  def disconnect
    Asana.disconnect!
    redirect_to asana_new_card_path
  end
end
