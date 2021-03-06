class User < ActiveRecord::Base
  extend FriendlyId
  friendly_id :username, use: [:finders]
  
  # orders user's based on creation date (for production)
  default_scope -> { order(:created_at) }

  has_many :microposts, dependent: :destroy
  has_many :active_relationships, class_name:  "Relationship",
                                  foreign_key: "follower_id",
                                  dependent:   :destroy
  has_many :passive_relationships, class_name:  "Relationship",
                                   foreign_key: "followed_id",
                                   dependent:   :destroy
  has_many :following, through: :active_relationships,
                       source: :followed
  has_many :followers, through: :passive_relationships,
                       source: :follower

  has_attached_file :avatar,
                    :styles => { :thumb => "50x50#",
                                 :small  => "100x100>",
                                 :medium => "200x200"   },
                    :default_url => ":style/default_avatar.png"

  attr_accessor :remember_token

  # before saving, change the user's email to all downcase to standardize DB.
  before_save { self.email = self.email.downcase unless self.email.nil?}
  before_create { }
  # A username must not be blank, must be between 4 and 30 characters,
  # must only consist of alphanumeric, underscore, and dash characters,
  # and has to be unique with no respect to case.
  VALID_USERNAME_REGEX = /\A[\w\-]+\z/
  validates(:username, { :presence   => true,
                         :length     => {minimum: 4, maximum: 30},
                         :format     => {with: VALID_USERNAME_REGEX},
                         :uniqueness => {case_sensitive: false}   })

  # A user's email is optional, but if it is filled in, it must follow
  # the valid email regex guidelines below, and must be below 255 characters.
  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
  validates(:email, { :allow_blank => true, 
                      :format => {with: VALID_EMAIL_REGEX},
                      :length => {maximum: 255}             })

  # A user's password must be at least 6 characters.
  validates(:password, { :length => {minimum: 6},
                         :presence => true,
                         :allow_nil => true      })

  # The following method encrypts the user's password in the database using
  # the BCrypt gem. This method adds the virtual attributes password and
  # password_confirmation. The following validations are also added:
  # password presence, password max length must be <= 72, confirmation
  # of password.
  has_secure_password

  validates_attachment :avatar, content_type: 
                              { content_type: ["image/jpg", "image/jpeg",
                                               "image/png", "image/gif"] }

  # Returns the hash digest of the given string.
  def User.digest(string)
    cost = ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST :
                                                  BCrypt::Engine.cost
    BCrypt::Password.create(string, cost: cost)
  end

  # Returns a random token.
  def User.new_token
    SecureRandom.urlsafe_base64
  end

  # Remembers a user in the database for use in persistent sessions.
  def remember
    self.remember_token = User.new_token
    update_attribute(:remember_digest, User.digest(remember_token))
  end

  # Returns true if the given token matches the digest.
  def authenticated?(remember_token)
    return false if remember_digest.nil?
    BCrypt::Password.new(remember_digest).is_password?(remember_token)
  end

  # Forgets a user.
  def forget
    update_attribute(:remember_digest, nil)
  end

  # Returns a user's status feed.
  # We optimizie this by pushing the followed user ids
  # into the database using a SQL subselect.
  def feed
    following_ids = "SELECT followed_id FROM relationships
                     WHERE  follower_id = :user_id"
    Micropost.where("user_id IN (#{following_ids})
                     OR user_id = :user_id", user_id: id)
  end

  def follow(other_user)
    active_relationships.create(followed_id: other_user.id)
  end

  def unfollow(other_user)
    active_relationships.find_by(followed_id: other_user.id).destroy
  end

  def following? (other_user)
    following.include?(other_user)
  end

  # Used for case-insensitive look-up.
  scope :ci_find, lambda { |attribute, value| where("lower(#{attribute}) = ?", value.downcase) }
end