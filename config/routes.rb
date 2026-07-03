Rails.application.routes.draw do
  root "boards#show"

  resource :board, only: :show
  resources :cards, only: [:new, :create, :show, :update] do
    member { patch :move }
    resources :messages, only: [:create]
  end
  resources :columns, only: [:create, :edit]
  resources :runs, only: [] do
    member do
      post :cancel
      post :approve
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
