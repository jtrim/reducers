### Actors

An `Actor` encapsulates an atomic unit of work, or in other words, it does one thing. This 'thing' _could_ be something as simple as updating a single record in the database, but in practice they tend to be made up of a multi-step transactional workflow (e.g. the debt rollover disbursement is a good example).

At its core, an `Actor` class responds to `::call` and `::call!`, which are the only two API methods consumers of actor classes need to know. Both take a hash as the only argument:

```ruby
result = UpdateUser.call(user: user, attributes: incoming_attributes)
```

Both forms return a hash that will have at least two keys: `:successful` and `:messages`. Although not required, `:messages` will generally be an empty array if the actor completes successfully. If `:successful` is falsy, then `:messages` should be an array of messages describing the failure.

```ruby
result = UpdateUser.call(user: user, attributes: incoming_attributes)
if result[:successful]
  redirect_to user_path(user)
else
  @errors = result[:messages]
  render :edit
end
```

The simplest definition of an actor might look like:

```ruby
class DoSomething < Reducers::Actor
  no_params
  no_result
  
  def call
    puts 'Did something!'
  end
end
```

**Declaring params and results**

`no_params` just says that the actor doesn't expect any incoming parameters. `no_result` says that the actor doesn't produce any values. Each can be replaced swapped out with `params` and `result`:

```ruby
class DoSomething < Reducers::Actor
  params :something
  result :something_else
  
  def call
    result.something_else = params.something.else
  end
end
```

Actors automatically validate that any declared `result` keys have values on the way out. The following would fail:

```ruby
class DoSomething < Actor # Superclass shortened for brevity
  no_params
  result :foo
  
  def call
    if false
      result.foo = 'bar'
    end      
  end
end

result = DoSomething.call #=> Reducers::Errors::FailureError: 
result[:successful] #=> false
result[:messages]   #=> ["Actor operation failed: Actor implementation did not set required result: :foo"]
```

**Required params**

Params can also be required:

```ruby
class DoSomething < Actor
  params foo: :required, bar: :optional
  no_result

  def call
    # ...
  end
end

result = DoSomething.call
result[:successful] #=> false
result[:messages]   #=> [':foo is required']
```

**`call!`**

`::call!` is just like `::call`, except it raises `Reducers::Errors::FailureError` with any `result[:messages]` if the actor operation fails:

```ruby
class DoSomething < Actor
  no_params
  no_result

  def call
    die 'whoops'
  end
end

DoSomething.call! #=> :boom: Reducers::Errors::FailureError: whoops
```

**`die`: Halting execution within an actor**

Speaking of `die`, that's how you signal that the operation has failed inside an actor:

```ruby
class UpdateUser < Actor
  params :user, :attributes
  no_result
  
  def call
    unless params.user.update(params.attributes)
      die params.user.errors.full_messages
    end
  end
end

class User < AR::Base
  validates_presence_of :first_name
end

result = UpdateUser.call(user: User.first, attributes: { first_name: nil })
result[:successful] #=> false
result[:messages]   #=> ['First name is required']
```

**`add_message`**

If you want to accumulate a few messages imperatively before signaling failure, `add_message` can be used:

```ruby
class DoSomething < Actor
  no_params
  no_result
  
  def call
    do_something_that_fails
  rescue SomethingFailed
    add_message 'something failed once'
    unless do_something_else_that_fails
      die 'the other thing failed too'
    end
  end
end

result = DoSomething.call
result[:successful] #=> false
result[:messages]   #=> ['something failed once', 'the other thing failed too']
```

If you find a use case to have an actor report a message even if the actor succeeds, `add_message` is your friend:

```ruby
class RegisterCreditCardWithMerchant < Actor
  params user: required, credit_card_number: required
  no_result
  
  def call
    merchant_response = Merchant.add_card(params.user.id, params.credit_card_number)
    add_message merchant_response.description
  end
end

result = RegisterCreditCardWithMerchant.call(user: user, credit_card_number: `4111111111111111`)
result[:successful] #=> true
result[:messages]   #=> ['Success code ABCD123']
```

...although an explicit result parameter is probably a better approach in this particular case.

**Delegators for free**

One last note on actor `call` definitions: by using `params :whatever`, you get delegators for free:

```ruby
class DoSomething < Actor
  params :whatever
  no_result
  
  def call
    puts params.whatever # this is cool
    puts whatever        # ...and so is this
  end
end
```

**Preconditions**

An actor also has the ability to precondition its execution on some arbitrary condition. Think of it like a guard clause:

```ruby
class DoSomething < Actor
  no_params
  no_result
  
  precondition :something_needs_done?
  
  def call
    puts 'executed'
  end
  
  def something_needs_done?
    true
  end
end

DoSomething.call #=> 'executed' is printed
```

Preconditions are optional. In the absence of a `precondition` configuration, the actor behaves the same as it would with a passing precondition.

The addition of `precondition` might seem superfluous. After all, why not imperatively define a guard condition in `#call`? Other than readability, using `precondition` has implications regarding the default logging actors produce.

**Logging**

The top-level `Reducers` module has a `logger`:

```ruby
Reducers.logger.info 'Something happened'           #=> INFO: Something happened
Reducers.logger.warn 'Hmm, something happened'      #=> WARNING: Hmm, something happened
Reducers.logger.error 'Oh no...something happened!' #=> ERROR: Oh no...something happened!
```

By default, actors log information about the circumstances of their execution. Continuing with the preceding `DoSomething` actor above:

```ruby
DoSomething.call
#=> INFO: Actor DoSomething was executed with params: {} : precondition :something_needs_done? evaluated to true
```

Or when the precondition doesn't pass:

```ruby
DoSomething.call
#=> INFO: Actor DoSomething was skipped with params: {} : precondition :something_needs_done? evaluated to false
```

In the absence of a precondition, this is produced instead:

```ruby
DoSomething.call
#=> INFO: Actor DoSomething was executed: no precondition defined
```

**`ActorDSL` for more concise actors**

To reduce boilerplate and make multiple actor definitions in one file more feasible, extend a namespace with ActorDSL:

```ruby
module ThingsToDo
  extend Reducers::ActorDSL

  actor result: [:baz], precondition: -> { foo == 'foo' }
  def DoSomething(foo:, bar: nil)
    die 'foo is invalid' if foo == 'invalid'
    result.baz = bar ? foo : 'nothing to do'
  end
end
```

The above example is exactly equivalent to:

```ruby
module ThingsToDo
  class DoSomething < Reducers::Actor
    params foo: :required, bar: :optional
    result :baz

    precondition :passes_precondition?

    def call
      die 'foo is invalid' if foo == 'invalid'
      result.baz = bar ? foo : 'nothing to do'
    end

    def passes_precondition?
      foo == 'foo'
    end
  end
end
```

**Filling the logic gap with `reduce_with`**

Actors are meant to contain the highly detailed domain / business logic to facilitate the functioning of a system. Reducers and Organizers (detailed below) are intended to aggregate actors into workflows, and should be totally dumb in terms of knowing about detailed business logic. So with only those two entities we end up with somewhat of a logic gap, where an operation needs to happen that involves many actors and the input parameters to those actors are context-specific, but the caller (a controller, background job, etc) shouldn't know about how those paramters are formed. Here's an example:

```ruby
class MeasureWater < Actor
  no_params
  result :water

  def call
    result.water = Water.in_milliliters(500)
  end
end

class GrindCoffee < Actor
  params :coffee_weight, :coffee_weight_unit
  result :coffee_grounds

  def call
    # ...
  end
end

class BrewCoffeeGrounds < Actor
  params :coffee_grounds, :water
  result :liquid_coffee

  def call
    # ...
  end
end

MakeCoffee = Organizer.create do
  add MeasureWater
  add GrindCoffee
  add BrewCoffeeGrounds
end

MakeCoffee.call(...)
```

In the above example, one of the goals of the system is to brew coffee in varying strengths. Who should decide how much coffee to add?

Let's assume coffee strength is a graduated concept, not a fluid one. In other words, the caller doesn't need to ask 'how many grams of coffee?', it really should ask 'Do you want weak, medium, or strong coffee?'

The consumer of `MakeCoffee` _could_ decide how much coffee to add:

```ruby
def coffee_request_handler(strength)
  result = case strength
  when :weak then MakeCoffee.call(coffee_weight: 30, coffee_weight_unit: :grams)
  when :medium then MakeCoffee.call(coffee_weight: 60, coffee_weight_unit: :grams)
  when :strong then MakeCoffee.call(coffee_weight: 90, coffee_weight_unit: :grams)
  end

  result[:liquid_coffee] if result[:successful]
end
```

\- but now `coffe_request_handler` knows too much about making coffee, since how it knows how much coffee constitutes a cup of a certain perceived strength. That seems like a detail we want to hide away in the business domain, but if `BrewCoffeeGrounds` is to be flexible enough to brew coffee with any water / coffee ratio and in any amounts, and MakeCoffee is to be completely dumb about the details of how work gets done, then who should decide?

Using `reduce_with`, use-case meta actors can be introduced to solve this conundrum:

```ruby
class MakeWeakCoffee < Actor # ...
class MakeMediumCoffee < Actor # ...

class MakeStrongCoffee < Actor
  no_params
  result :liquid_coffee

  def call
    reduce_with(coffee_weight: 90, coffee_weight_unit: :grams)) do
      add MeasureWater
      add GrindCoffee
      add BrewCoffeeGrounds
    end
  end
end
```

\- then our handler that responds to requests for coffee of varying strengths improves:

```ruby
def coffee_request_handler(strength)
  result = case strength
  when :weak then MakeWeakCoffee.call
  when :medium then MakeMediumCoffee.call
  when :strong then MakeStrongCoffee.call
  end

  result[:liquid_coffee] if result[:successful]
end
```

### Organizers

`Organizer` instances group multiple actors together:

```ruby
module Borrower
  LoanMaintenance = Reducers::Organizer.create do
    add SetLoanTermOnDisbursementWindowClose
    add JournalPeriod
    add GeneratePaymentSchedule
    add RemindBorrowerOfUpcomingPayment
  end
end
```

They respond to the same public interfaces as actors, except they return a slightly different result:

```ruby
result = Borrower::LoanMaintenance.call(period: period, loan: loan)

result #=> [{ successful: true, messages: [] },
       #    { successful: true, messages: [] },
       #    { successful: false, messages: ['Payment schedule document failed to save'] },
       #    { successful: true, messages: [] }]
       
# Also drops a log entry:
# WARNING: Actor GeneratePaymentSchedule failed within an organizer. Messages: ["Payment schedule document failed to save"]       
```

One thing you migth notice about the above example is that the 3rd actor failed (note the log message), but the 4th actor still ran. `Organizer#call` doesn't short-circuit the operation, but `Organizer#call!` does:

```ruby
Borrower::LoanMaintenance.call!(period: period, loan: loan) #=> :boom: Reducers::Errors::FailureError: Payment schedule document failed to save
```

...and it also raises the same exception that `Actor::call!` does, since internally `Organizer` uses that actor method instead of `Actor::call`. In the above example, `RemindBorrowerOfUpcomingPayment` is never called.

An organizer can be created and managed in a more imperative-looking way:

```ruby
og = Reducers::Organizer.new # or .create
og.add(Something)
og.add(SomethingElse) if foo?

og.actors #=> [Something, SomethingElse]
```

**Using `#around` to wrap the actor execution context**

To facilate transactional organizers, use `around` when creating an organizer:

```ruby
DoSomething = Reducers::Organizer.create do
  add Something
  add SomethingElse
  
  around do |&actors|
    DatabaseAdapter.transaction do
      actors.call
    end
    # Or more succinctly:
    # DatabaseAdapter.transaction(&actors)
  end
end
```

**Using `#on_failure` to respond to actor failure**

If you want to take action in response to an actor failure, use `on_failure`:

```ruby
DoSomething = Reducers::Organizer.create do
  add Something
  add SomethingElse
  
  on_failure do |result|
    AdminNotifier.notify(result[:messages])
  end
end
```

The `on_failure` block receives one argument: the `result` hash of the actor that failed.

`around` and `on_failure` can be used in combination to roll back a database transaction when an actor fails but doesn't generate an exception:

```ruby
DoSomething = Reducers::Organizer.create do
  add Something
  add SomethingElse
  
  around do |&actors|
    DatabaseAdapter.transaction(&actors)
  end
  
  on_failure do |result|
    raise DatabaseAdapter::Rollback
  end
end
```

**Using `precondition` to let an organizer decide if an actor applies**

Actor preconditions and guard clauses will tend to be fairly general. In other words, an actor might need to be invoked directly to handle a specific use case, but also invoked on some schedule to respond to a conceptual event, such as the passing of a certain time. Organizers can assign additional preconditions at the actor level to add to the precondition check the actor will perform:

```ruby
class DoSomething < Actor
  params foo: :required
  no_result

  precondition :foo_has_bar?

  def call
    # ...
  end

  def foo_has_bar?
    !params.foo.bar.nil?
  end
end

DoSomething = Reducers::Organizer.create do
  add Something
  add SomethingElse, precondition: -> (foo:, **) { foo.created_date < Date.today - 7 }
  add OneLastThing
end
```

Organizer-level preconditions and actor preconditions are additive. Above, `foo` would have to have a `.bar` **and** be seven days old before `SomethingElse` will be invoked by the `DoSomething` organizer.

### Reducers

`Reducer` instances are basically organizers, except instead of running each actor in isolation from eachother, the result is accumulated as params / results flow through the actor chain:

```ruby
class FindThing < Actor
  params :thing_id
  result :thing
  
  def call
    result.thing = ThingAPI.lookup(id: thing_id)
  end
end

class UpdateThing < Actor
  params :thing, :thing_attributes
  no_result
  
  def call
    unless ThingAPI.update(thing_id: thing.uuid, **thing_attributes)
      die "Thing #{thing.id} was not updated"
    end
  end
end

class NotifyUserThingHappened < Actor
  params :user, :thing
  no_result
  
  def call
    ThingMailer.default_notification(user, thing).deliver_later
  end
end

UpdateThingBecauseReasons = Reducers::Reducer.create do
  add FindThing
  add UpdateThing
  add NotifyUserThingHappened
end

result = UpdateThingBecauseReasons.call(user: user, thing_id: thing_id, thing_attributes: attrs)
result.inspect #=> {
               #     successful: true,
               #     messages:   [],
               #     thing_id:   1,
               #     thing:      <#Thing:0xABCD123 ...>,
               #     user:       <#User:0x0011332 ...>
               #   }
```

In the above example, `FindThing` emits a `thing` result value, which is merged into the initial input parameters. As the reduction proceeds, the accumulator is passed into each subsequent actor until all actors have been called.

If an actor fails in the middle of the operation:

```ruby
result = UpdateThingBecauseReasons.call(user: user, thing_id: thing_id, thing_attributes: attrs) # UpdateThing fails
result[:successful] #=> false
result[:messages]   #=> ['Thing 1 was not updated']
```

In the preceding example, `NotifyUserThingHappened` wasn't executed because the actor immediately before it failed.

Since actors define `params` and `results`, a reducer can know whether or not it was given the necessary initial paramters for every actor to meet its requirements:

```ruby
class Something < Actor
  no_params
  result :foo
  def call
    # ...
  end
end

class SomethingElse < Actor
  params foo: required, bar: required, meh: optional
  no_result
  def call
    # ...
  end
end

DoSomething = Reducers::Reducer.create do
  add Something
  add SomethingElse
end

DoSomething.call             #=> :boom: Reducers::Errors::UnproducedParameterError
DoSomething.call(bar: 'bar') #=> { successful: true, messages: [] }
```

**`#around` and `#on_failure`**

Both `around` and `on_failure` work the same way for a `Reducer` as for an `Organizer`
