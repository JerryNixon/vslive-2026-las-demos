const { useState, useEffect } = React;

function App() {
  const [warehouses, setWarehouses] = useState([]);
  const [products, setProducts] = useState({});
  const [inventory, setInventory] = useState({});
  const [expanded, setExpanded] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function load() {
      const [whRes, prodRes] = await Promise.all([
        fetch("/api/Warehouse").then(r => r.json()),
        fetch("/api/Product").then(r => r.json()),
      ]);

      setWarehouses(whRes.value || []);

      const names = {};
      for (const p of prodRes.value || []) {
        names[p.ProductId] = p.Name;
      }
      setProducts(names);
      setLoading(false);
    }
    load();
  }, []);

  async function toggle(warehouseId) {
    if (expanded === warehouseId) {
      setExpanded(null);
      return;
    }
    if (!inventory[warehouseId]) {
      const res = await fetch(`/api/Inventory?$filter=WarehouseId eq ${warehouseId}`);
      const data = await res.json();
      setInventory(prev => ({ ...prev, [warehouseId]: data.value || [] }));
    }
    setExpanded(warehouseId);
  }

  if (loading) {
    return (
      <div className="container mt-4">
        <p className="text-muted">Loading...</p>
      </div>
    );
  }

  return (
    <div className="container mt-4">
      <h1 className="mb-4">Warehouse Summary</h1>

      {warehouses.length === 0 && (
        <div className="alert alert-info">No warehouses found.</div>
      )}

      <div className="accordion" id="warehouseAccordion">
        {warehouses.map(w => (
          <div className="accordion-item" key={w.WarehouseId}>
            <h2 className="accordion-header">
              <button
                className={`accordion-button ${expanded === w.WarehouseId ? "" : "collapsed"}`}
                type="button"
                onClick={() => toggle(w.WarehouseId)}
              >
                <strong>{w.Name}</strong>
                <span className="text-muted ms-2">— {w.Location}</span>
              </button>
            </h2>
            {expanded === w.WarehouseId && (
              <div className="accordion-collapse collapse show">
                <div className="accordion-body">
                  {!inventory[w.WarehouseId] ? (
                    <p className="text-muted">Loading inventory...</p>
                  ) : inventory[w.WarehouseId].length === 0 ? (
                    <p className="text-muted">No inventory at this warehouse.</p>
                  ) : (
                    <table className="table table-sm table-striped mb-0">
                      <thead>
                        <tr>
                          <th>Product</th>
                          <th>Quantity</th>
                        </tr>
                      </thead>
                      <tbody>
                        {inventory[w.WarehouseId].map(item => (
                          <tr key={item.InventoryId}>
                            <td>{products[item.ProductId] || `Product ${item.ProductId}`}</td>
                            <td>{item.Quantity}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
