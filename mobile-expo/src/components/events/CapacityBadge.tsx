import { Badge } from "@/components/ui/Badge";

/** Byte-for-byte port of web/src/components/events/CapacityBadge.tsx's thresholds. */
export function CapacityBadge({
  confirmed,
  capacity,
  isLoading = false,
}: {
  confirmed: number | undefined;
  capacity: number;
  isLoading?: boolean;
}): React.JSX.Element {
  if (isLoading || confirmed === undefined) {
    return (
      <Badge variant="outline" pulse>
        {`…/${capacity}`}
      </Badge>
    );
  }

  const remaining = capacity - confirmed;
  const variant = remaining <= 0 ? "destructive" : remaining <= Math.max(1, Math.ceil(capacity * 0.1)) ? "warning" : "success";
  const label = remaining <= 0 ? `Full · ${confirmed}/${capacity}` : `${confirmed}/${capacity} booked`;

  return <Badge variant={variant}>{label}</Badge>;
}
