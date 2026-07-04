Rails.application.routes.draw do
  root "boards#show"

  resource :board, only: :show do
    post :deep_dive
    post :pull
    get :brief
  end
  resources :cards, only: [:new, :create, :show, :update, :destroy] do
    member do
      patch :move
      post :approve
    end
    resources :messages, only: [:create]
  end
  resources :columns, only: [:create, :edit, :update, :destroy]
  resources :runs, only: [] do
    member do
      post :cancel
      post :approve
      post :restart
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
