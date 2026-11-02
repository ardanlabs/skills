# Domain Events

Part of `ardan-service-architecture`.

A domain announces that something happened (e.g. "user deleted") without knowing who reacts. Other domains subscribe through the in-process dispatcher (`business/sdk/delegate`). Use events when a domain must react to another domain's change. They do not replace queries: when a domain needs another domain's data, it imports that domain's `*bus` (see SKILL.md).

## Event definitions live with the publisher (MUST)

- Each publishing domain `<y>` defines its events in `business/domain/<y>bus/event.go`: `DomainName`, the `Action<Name>` constants, an `Action<Name>Params` type per action, and an `Action<Name>Data` constructor that returns `delegate.Data`.
- Subscribers import `<y>bus` for those definitions and register their handlers in their own `event.go` (`registerDelegateFunctions`).
- Only domain `<y>` publishes `<y>bus` actions.

## Events are part of the transaction (MUST)

- The dispatcher passes the publisher's transaction to every handler: `type Func func(ctx context.Context, tx sqldb.CommitRollbacker, data Data) error`, called as `delegate.Call(ctx, tx, data)`.
- A publisher whose handlers can write state must itself run inside the App-owned transaction (see SKILL.md). The tx-bound Business (`NewWithTx`) keeps the tx and passes it to `Call`.
- Every handler that reads or writes state first binds itself to that tx (`bus, err := b.NewWithTx(tx)`) and does all its work through `bus`. Working through the base `b` silently escapes the transaction.
- A handler error propagates back through `Call` to the publisher, which returns it, so the App layer rolls the whole transaction back.
- Side effects that leave the process (message broker, email, webhook) can't join a DB transaction. Don't do them in a handler. Write them to an outbox table inside the same tx and deliver them after commit. Confirm the outbox design with the user before building one.

## Example

```go
// business/domain/userbus/event.go
package userbus

const DomainName = "user"

const ActionDeleted = "deleted"

type ActionDeletedParams struct {
	UserID uuid.UUID `json:"user_id"`
}

func ActionDeletedData(userID uuid.UUID) (delegate.Data, error) {
	raw, err := json.Marshal(ActionDeletedParams{UserID: userID})
	if err != nil {
		return delegate.Data{}, fmt.Errorf("marshal deleted params: %w", err)
	}

	return delegate.Data{Domain: DomainName, Action: ActionDeleted, RawParams: raw}, nil
}
```

```go
// business/domain/userbus/userbus.go (publisher; b is tx-bound)
func (b *Business) Delete(ctx context.Context, usr User) error {
	if err := b.storer.Delete(ctx, usr); err != nil {
		return fmt.Errorf("delete: %w", err)
	}

	data, err := ActionDeletedData(usr.ID)
	if err != nil {
		return fmt.Errorf("deleted event: %w", err)
	}

	if err := b.delegate.Call(ctx, b.tx, data); err != nil {
		return fmt.Errorf("call %s.%s: %w", DomainName, ActionDeleted, err)
	}

	return nil
}
```

```go
// business/domain/homebus/event.go (subscriber)
func (b *Business) registerDelegateFunctions() {
	if b.delegate != nil {
		b.delegate.Register(userbus.DomainName, userbus.ActionDeleted, b.actionUserDeleted)
	}
}

func (b *Business) actionUserDeleted(ctx context.Context, tx sqldb.CommitRollbacker, data delegate.Data) error {
	var params userbus.ActionDeletedParams
	if err := json.Unmarshal(data.RawParams, &params); err != nil {
		return fmt.Errorf("unmarshal %T: %w", params, err)
	}

	bus, err := b.NewWithTx(tx)
	if err != nil {
		return fmt.Errorf("new with tx: %w", err)
	}

	return bus.deleteByUser(ctx, params.UserID)
}
```

## Conformance checklist

- [ ] Event definitions are in the publisher's `<y>bus/event.go` (`DomainName`, `Action<Name>`, `Action<Name>Params`, `Action<Name>Data`).
- [ ] The publisher runs inside the App-owned tx and passes it to `delegate.Call`.
- [ ] Every handler binds to the passed tx via `NewWithTx` before touching state, and returns its errors.
- [ ] No external side effect inside a handler; an outbox (user-approved) is used instead.
- [ ] Events aren't used as a substitute for cross-domain queries.
