Rails.application.routes.draw do
  root "boards#show"

  resource :board, only: :show
  resources :cards, only: [:create, :show] do
    member { patch :move }
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
