# Shared model-name formatting for the two places a model+effort pair is
# resolved and shown: a Column's own policy and a Card's effective (possibly
# overridden) config. Kept in one place so a card face and its column can never
# disagree about how a model reads — the board must not misreport what spends.
module ModelLabeling
  extend ActiveSupport::Concern

  # "claude-sonnet-4-6" → "sonnet"; passes through a non-claude name unchanged.
  def model_short_of(model_name)
    model_name.to_s[/claude-([a-z]+)/, 1] || model_name.presence
  end

  # "Opus - High" — human label from a model + optional effort. Effort is
  # optional, so a model with no effort renders just "Opus". Blank model → nil.
  def model_label_of(model_name, effort_name)
    return if model_name.blank?
    label = model_short_of(model_name).to_s.capitalize
    effort_name.present? ? "#{label} - #{effort_name.to_s.capitalize}" : label
  end
end
