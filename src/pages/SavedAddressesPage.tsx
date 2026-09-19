import { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { safeGoBack } from '@/lib/utils';
import { motion } from 'framer-motion';
import { ArrowLeft, Plus, MapPin, Loader2 } from 'lucide-react';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { AddressCard } from '@/components/address/AddressCard';
import { AddressFormDialog } from '@/components/address/AddressFormDialog';
import { useSavedAddresses, type SavedAddress, type SavedAddressInput } from '@/hooks/useSavedAddresses';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';

export default function SavedAddressesPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const isSelecting = searchParams.get('select') === '1';
  const { addresses, loading, addAddress, updateAddress, deleteAddress, setDefaultAddress } = useSavedAddresses();
  
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingAddress, setEditingAddress] = useState<SavedAddress | null>(null);
  const [deleteId, setDeleteId] = useState<string | null>(null);

  const handleSelect = (address: SavedAddress) => {
    const addressText = address.full_address || [
      address.address_detail,
      address.village_name,
      address.district_name,
      address.city_name,
    ].filter(Boolean).join(', ');
    localStorage.setItem('sadesa-selected-address', JSON.stringify({
      id: address.id,
      label: address.label,
      address: addressText || address.label,
      lat: address.lat,
      lng: address.lng,
    }));
    window.dispatchEvent(new Event('sadesa-address-selected'));
    navigate(-1);
  };

  const handleEdit = (address: SavedAddress) => {
    setEditingAddress(address);
    setDialogOpen(true);
  };

  const handleAdd = () => {
    setEditingAddress(null);
    setDialogOpen(true);
  };

  const handleSave = async (data: SavedAddressInput) => {
    if (editingAddress) {
      return updateAddress(editingAddress.id, data);
    } else {
      return addAddress(data);
    }
  };

  const handleDelete = async () => {
    if (deleteId) {
      await deleteAddress(deleteId);
      setDeleteId(null);
    }
  };

  return (
    <div className="mobile-shell bg-background flex flex-col min-h-screen">
      <Header />
      
      <div className="flex-1 overflow-y-auto pb-24">
        <motion.div 
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="px-5 py-4"
        >
          {/* Header */}
          <div className="flex items-center gap-3 mb-6">
            <Button variant="ghost" size="icon" onClick={() => safeGoBack(navigate)}>
              <ArrowLeft className="h-5 w-5" />
            </Button>
            <div className="flex-1">
              <h1 className="text-xl font-bold">{isSelecting ? 'Pilih alamat pengantaran' : 'Alamat Tersimpan'}</h1>
              <p className="text-sm text-muted-foreground">
                {isSelecting ? 'Pilih alamat untuk pesanan ini atau tambahkan alamat baru.' : 'Kelola alamat pengiriman Anda'}
              </p>
            </div>
            <Button onClick={handleAdd} size="sm">
              <Plus className="h-4 w-4 mr-1" />
              Tambah
            </Button>
          </div>

          {loading ? (
            <div className="flex items-center justify-center py-12">
              <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
            </div>
          ) : addresses.length === 0 ? (
            <div className="text-center py-12">
              <div className="w-16 h-16 rounded-full bg-muted flex items-center justify-center mx-auto mb-4">
                <MapPin className="h-8 w-8 text-muted-foreground" />
              </div>
              <h3 className="font-medium mb-1">Belum ada alamat tersimpan</h3>
              <p className="text-sm text-muted-foreground mb-4">
                Tambahkan alamat untuk mempercepat proses checkout
              </p>
              <Button onClick={handleAdd}>
                <Plus className="h-4 w-4 mr-2" />
                Tambah Alamat
              </Button>
            </div>
          ) : (
            <div className="space-y-3">
              {addresses.map((address) => (
                <AddressCard
                  key={address.id}
                  address={address}
                  onEdit={isSelecting ? undefined : handleEdit}
                  onDelete={isSelecting ? undefined : (id) => setDeleteId(id)}
                  onSetDefault={isSelecting ? undefined : setDefaultAddress}
                  onSelect={isSelecting ? handleSelect : undefined}
                  selectable={isSelecting}
                />
              ))}
            </div>
          )}
        </motion.div>
      </div>
      
      <BottomNav />

      {/* Add/Edit Dialog */}
      <AddressFormDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        address={editingAddress}
        onSave={handleSave}
      />

      {/* Delete Confirmation */}
      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Hapus Alamat?</AlertDialogTitle>
            <AlertDialogDescription>
              Alamat ini akan dihapus secara permanen. Tindakan ini tidak dapat dibatalkan.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Batal</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} className="bg-destructive text-destructive-foreground">
              Hapus
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
