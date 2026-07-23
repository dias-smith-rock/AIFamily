"use client";

import { MapContainer, Marker, Popup, TileLayer } from "react-leaflet";
import "leaflet/dist/leaflet.css";

export interface MapMember {
  id: string;
  name: string;
  lat: number;
  lng: number;
  updatedAt: string;
  isGhost?: boolean;
}

const DEFAULT_CENTER: [number, number] = [22.3193, 114.1694];

export function LocationMap({ members }: { members: MapMember[] }) {
  const center: [number, number] =
    members.length > 0 ? [members[0].lat, members[0].lng] : DEFAULT_CENTER;

  return (
    <MapContainer center={center} zoom={13} scrollWheelZoom={false} style={{ height: 280, width: "100%", borderRadius: 14 }}>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      {members.map((member) => (
        <Marker key={member.id} position={[member.lat, member.lng]}>
          <Popup>
            <strong>{member.name}</strong>
            {member.isGhost ? <p>Ghost mode</p> : null}
            <p>{new Date(member.updatedAt).toLocaleString()}</p>
          </Popup>
        </Marker>
      ))}
    </MapContainer>
  );
}
