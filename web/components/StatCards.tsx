export function StatCards({ cards }: { cards: { big: string; label: string }[] }) {
  return (
    <div className="cards">
      {cards.map((c) => (
        <div className="card" key={c.label}>
          <div className="big">{c.big}</div>
          <div className="label">{c.label}</div>
        </div>
      ))}
    </div>
  );
}
