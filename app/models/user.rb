class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable, invitable
  # Extensions
  #include Stripe::Callbacks
  
  devise :invitable, :database_authenticatable, :registerable, :lockable, :timeoutable, 
         :recoverable, :rememberable, :trackable, :validatable, :authentication_keys => [:login]

  validates :username, presence: true
  #validates_uniqueness_of :username, presence: true
  
  # Virtual attribute for authenticating by either user_id or email
  # This is in addition to a real persisted field like 'user_id'
  attr_accessor :login

  def login=(login)
    @login = login
  end

  def login
    @login || self.username || self.email
  end

  def self.find_for_database_authentication(warden_conditions)
    conditions = warden_conditions.dup
    if login = conditions.delete(:login)
      where(conditions.to_h).where(["username = :value OR email = :value", { :value => login.downcase }]).first
    else
      where(conditions.to_h).first
    end
  end
  
  def send_devise_notification(notification, *args)
    #devise_mailer.send(notification, self, *args).deliver_later
    devise_mailer.send(notification, self, *args).deliver_now
  end
  
  # Methods
  def do_deposit_transaction(type, stripe_token)
    amount = Transaction.amount_for_type(type)
    coupon = UserCoupon.coupon_for_amount(amount)

    card = save_credit_card(stripe_token)
    if deposited = deposit(amount, card)
      subscribe if type == 'subscription'
      create_coupon(coupon) if coupon

      deposited
    end
  end

  def stripe_customer
    Stripe::Customer.retrieve(stripe_customer_id)
  end

  def deposit(amount, card)
    customer = stripe_customer

    Stripe::Charge.create(
      amount: amount,
      currency: 'usd',
      customer: customer.id,
      card: card.id,
      description: "Charge for #{email}"
    )

    customer.account_balance += amount
    customer.save
  rescue => e
    false
  end
  
  private

  def subscribe
    stripe_customer.subscriptions.create(plan: 'monthly')
  end

  def create_coupon(coupon)
    customer = stripe_customer
    already_has_off3_coupon = customer.discount && customer.discount.any? { |type, co| type == :coupon && co.id == 'off3' }

    return true if coupon == 'off3' && already_has_off3_coupon

    customer.coupon = coupon
    customer.save
  end

  def create_stripe_customer
    customer = Stripe::Customer.create(email: email, account_balance: 0)
    self.stripe_customer_id = customer.id
  end

  def save_credit_card(card_token)
    stripe_customer.cards.create(card: card_token)
  end
end
