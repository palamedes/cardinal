Rails.application.routes.draw do
  root "boards#show"

  resource :board, only: :show
  resources :cards, only: [:new, :create, :show, :update] do
    member do
      patch :move
      post :approve
      post :request_changes
    end
    resources :messages, only: [:create]
  end
  resources :columns, only: [:create, :edit, :update, :destroy]
  resources :runs, only: [] do
    member do
      post :cancel
      post :approve
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
