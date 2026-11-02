# Domain Events

Part of `ardan-service-architecture`.

A domain announces that something happened (e.g. "user deleted") without knowing who reacts. Other domains subscribe through the in-process dispatcher (`business/sdk/delegate`). Events are the way to react to another domain's changes. They do not replace queries: when a domain needs data from another domain, a coordinator (see SKILL.md) fetches it and passes it in.

## Event definitions live in a shared leaf (MUST)

- Each publishing domain `<y>` defines its events in `business/types/event/<y>event`, never in `<y>bus`. The package holds the domain name, the action names, the params types, and a constructor per action that returns `delegate.Data`.
- `business/types/event/*` is a shared leaf: it may import only `foundation/*`, other `business/types/*` packages, and `business/sdk/delegate`. It must never import an App, Business domain, store, or coordinator package.
- Publishers and subscribers both import `business/types/event/<y>event`. A subscriber never imports `<y>bus` to get event names or params.
- Only domain `<y>` publishes `<y>event` actions.

## Events are part of the transaction (MUST)

- The dispatcher passes the publisher's transaction to every handler: `type Func func(ctx context.Context, tx sqldb.CommitRollbacker, data Data) error`, called as `delegate.Call(ctx, tx, data)`.
- A publisher whose handlers can write state must itself run inside a transaction owned by its coordinator. The tx-bound Business (`NewWithTx`) keeps the tx and passes it to `Call`.
- Every handler that reads or writes state first binds itself to that tx (`bus, err := b.NewWithTx(tx)`) and does all its work through `bus`. Working through the base `b` silently escapes the transaction.
- A handler error propagates back through `Call` to the publisher, which returns it, so the coordinator rolls the whole transaction back.
- Side effects that leave the process (message broker, email, webhook) can't join a DB transaction. Don't do them in a handler. Write them to an outbox table inside the same tx and deliver them after commit. Confirm the outbox design with the user before building one.

## Example

```go
// business/types/event/userevent/userevent.go
package userevent

const Domain = "user"

const ActionDeleted = "deleted"

type DeletedParams struct {
	UserID uuid.UUID `json:"user_id"`
}

func DeletedData(userID uuid.UUID) (delegate.Data, error) {
	raw, err := json.Marshal(DeletedParams{UserID: userID})
	if err != nil {
		return delegate.Data{}, fmt.Errorf("marshal deleted params: %w", err)
	}

	return delegate.Data{Domain: Domain, Action: ActionDeleted, RawParams: raw}, nil
}
```

```go
// business/domain/userbus/userbus.go (publisher; b is tx-bound)
func (b *Business) Delete(ctx context.Context, usr User) error {
	if err := b.storer.Delete(ctx, usr); err != nil {
		return fmt.Errorf("delete: %w", err)
	}

	data, err := userevent.DeletedData(usr.ID)
	if err != nil {
		return fmt.Errorf("deleted event: %w", err)
	}

	if err := b.delegate.Call(ctx, b.tx, data); err != nil {
		return fmt.Errorf("call %s.%s: %w", userevent.Domain, userevent.ActionDeleted, err)
	}

	return nil
}
```

```go
// business/domain/homebus/event.go (subscriber)
func (b *Business) registerDelegateFunctions() {
	if b.delegate != nil {
		b.delegate.Register(userevent.Domain, userevent.ActionDeleted, b.actionUserDeleted)
	}
}

func (b *Business) actionUserDeleted(ctx context.Context, tx sqldb.CommitRollbacker, data delegate.Data) error {
	var params userevent.DeletedParams
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

- [ ] Event definitions are in `business/types/event/<y>event`, which imports only `foundation/*`, `business/types/*`, and `business/sdk/delegate`.
- [ ] No subscriber imports the publisher's `*bus` package.
- [ ] The publisher runs inside a coordinator-owned tx and passes it to `delegate.Call`.
- [ ] Every handler binds to the passed tx via `NewWithTx` before touching state, and returns its errors.
- [ ] No external side effect inside a handler; an outbox (user-approved) is used instead.
- [ ] Events aren't used as a substitute for cross-domain queries.
