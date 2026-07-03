Rails.application.routes.draw do
  root "boards#show"

  resource :board, only: :show
  resources :cards, only: [:create, :show, :update] do
    member { patch :move }
  end
  resources :columns, only: [:create]

  get "up" => "rails/health#show", as: :rails_health_check
end
