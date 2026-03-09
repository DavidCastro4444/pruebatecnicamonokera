class ProcessedEvent < ApplicationRecord
  validates :event_id, presence: true, uniqueness: true
  validates :processed_at, presence: true
end
