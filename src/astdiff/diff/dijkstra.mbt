///|UUID(0b68f529-4c5b-42fe-8a34-07ecd4f883ef)
/// Implements Dijkstra's algorithm for shortest path, to find an
/// optimal and readable diff between two ASTs.
suberror ExceededGraphLimit {
  ExceededGraphLimit
}

///|UUID(58abb95f-c5cc-4ced-8d34-ca251ed41672)
#valtype
priv struct WeightedVertex {
  vertex : Vertex
  distance : @cmp.Reverse[UInt]
} derive(Eq)

///|UUID(5b821e8f-5dc5-43ea-b19b-6473450629cd)
impl Compare for WeightedVertex with compare(self, other) {
  self.distance.compare(other.distance)
}

///|UUID(976c6dd4-d919-4feb-a129-52592577ac53)
/// Return the shortest route from `start` to the end vertex.
fn shortest_vertex_path(
  start : Vertex,
  size_hint : Int,
  graph_limit : Int,
) -> Array[Vertex] raise ExceededGraphLimit {
  // We want to visit nodes with the shortest distance first, but
  // PriorityQueue is a max-heap. Ensure nodes are wrapped with
  // @cmp.Reverse to flip comparisons.
  let heap = PriorityQueue::new()
  heap.push(WeightedVertex::{ vertex: start, distance: @cmp.Reverse(0) })
  let seen = HashMap::new(capacity=size_hint)
  let end : Vertex = loop heap.pop() {
    Some({ vertex: current, distance: Reverse(distance) }) => {
      if current.is_end() {
        break current
      }
      set_neighbours(current, seen)
      for neighbor in current.neighbours.val.unwrap() {
        let (edge, next) = neighbor
        let distance_to_next = distance + edge.cost()
        let found_shorter_route = match next.predecessor.val {
          Some((prev_shortest, _)) => distance_to_next < prev_shortest
          None => true
        }
        if found_shorter_route {
          next.predecessor.update(_ => Some((distance_to_next, current)))
          heap.push(WeightedVertex::{
            vertex: next,
            distance: @cmp.Reverse(distance_to_next),
          })
        }
      }
      if seen.length() > graph_limit {
        raise ExceededGraphLimit
      }
      continue heap.pop()
    }
    None => panic() // Ran out of graph nodes before reaching end
  }
  let mut current = Some((0U, end))
  let vertex_route = Array::new()
  while current is Some((_, node)) {
    vertex_route.push(node)
    current = node.predecessor.val
  }
  vertex_route.rev_in_place()
  return vertex_route
}

///|UUID(2a51db63-c593-4a88-a1d8-efbcb82369c8)
/// Return the shortest route from the `start` to the end vertex.
///
/// The vec returned does not return the very last vertex. This is
/// necessary because a route of N vertices only has N-1 edges.
fn shortest_path_with_edges(route : Array[Vertex]) -> Array[(Edge, Vertex)] {
  let mut prev = route.get(0).unwrap_or_else(() => panic())
  // let mut cost = 0U
  let res = Array::new()
  for vertex in route.iter().drop(1) {
    let edge = edge_between(prev, vertex)
    res.push((edge, prev))
    // cost += edge.cost()
    prev = vertex
  }
  res
}

///|UUID(bc2f5db2-b5a0-442c-80b0-f377da42303c)
/// Return the shortest route from the `start` to the end vertex.
///
/// The vec returned does not return the very last vertex. This is
/// necessary because a route of N vertices only has N-1 edges.
pub fn shortest_path(
  start : Vertex,
  size_hint : Int,
  graph_limit : Int,
) -> Array[(Edge, Vertex)] raise ExceededGraphLimit {
  let vertex_path = shortest_vertex_path(start, size_hint, graph_limit)
  shortest_path_with_edges(vertex_path)
}

///|UUID(7491a578-084f-4361-b488-58b7f2f8cb56)
fn edge_between(before : Vertex, after : Vertex) -> Edge {
  let mut shortest_edge : Edge? = None
  if before.neighbours.val is Some(neighbours) {
    for neighbour in neighbours {
      let (edge, next) = neighbour
      // If there are multiple edges that can take us to `next`,
      // prefer the shortest.
      if next == after {
        let is_shorter = match shortest_edge {
          Some(prev_edge) => edge.cost() < prev_edge.cost()
          None => true
        }
        if is_shorter {
          shortest_edge = Some(edge)
        }
      }
    }
  }
  if shortest_edge is Some(edge) {
    return edge
  }
  panic() // 
}

///|UUID(a896833c-4b57-407b-a10b-a4e42597340c)
/// What is the total number of AST nodes?
fn node_count(root : Syntax?) -> UInt {
  let iter = root.succ(node => node.next_sibling())
  iter
  .map(node => match node {
    List(num_descendants~, ..) => num_descendants
    Atom(..) => 1
  })
  .fold(init=0U, (x, y) => x + y)
}

///|UUID(e496578b-e165-449e-9e33-d3cc82d8db71)
/// How many top-level AST nodes do we have?
pub fn tree_count(root : Syntax?) -> UInt {
  root.succ(node => node.next_sibling()).count().reinterpret_as_uint()
}

///|UUID(a24b0dfa-1df3-4fcb-b1c2-4355dd4083a5)
pub fn mark_syntax(
  lhs_syntax : Syntax?,
  rhs_syntax : Syntax?,
  change_map : ChangeMap,
  graph_limit : UInt,
) -> Unit raise ExceededGraphLimit {
  let lhs_node_count = node_count(lhs_syntax)
  let rhs_node_count = node_count(rhs_syntax)

  // When there are a large number of changes, we end up building a
  // graph whose size is roughly quadratic. Use this as a size hint,
  // so we don't spend too much time re-hashing and expanding the
  // predecessors hashmap.
  //
  // Cap this number to the graph limit, so we don't try to allocate
  // an absurdly large (i.e. greater than physical memory) hashmap
  // when there is a large number of nodes. We'll never visit more
  // than graph_limit nodes.

  let size_hint = @cmp.minimum(lhs_node_count * rhs_node_count, graph_limit).reinterpret_as_int()
  let start = Vertex::new(lhs=lhs_syntax, rhs=rhs_syntax)
  let route = shortest_path(start, size_hint, graph_limit.reinterpret_as_int())
  populate_change_map(route, change_map)
}

///|UUID(b0f991cc-c1d3-4f68-998a-594ad3288a07)
fn[T] Option::succ(self : T?, f : (T) -> T?) -> Iterator[T] {
  let mut curr = self
  Iterator::new(() => {
    let prev = curr
    curr = match curr {
      Some(x) => f(x)
      None => None
    }
    return prev
  })
}
