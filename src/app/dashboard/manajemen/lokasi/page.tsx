'use client'

import { useState, useEffect } from 'react'
import { getLocations, updateLocation, deleteLocation } from '@/lib/actions/locations'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Edit, Trash2, Search } from 'lucide-react'
import { useToast } from '@/hooks/use-toast'

interface Location {
  location_id: string
  customer_id: string
  building_name: string
  floor: number
  room_number: string
  description: string
  customers?: {
    customer_id: string
    customer_name: string
    phone_number: string
    primary_contact_person?: string
    email?: string
  }
}

export default function LocationsPage() {
  const { toast } = useToast()
  const [locations, setLocations] = useState<Location[]>([])
  const [loading, setLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')
  const [isEditOpen, setIsEditOpen] = useState(false)
  const [isDeleteOpen, setIsDeleteOpen] = useState(false)
  const [selectedLocation, setSelectedLocation] = useState<Location | null>(null)
  const [deleteId, setDeleteId] = useState<string | null>(null)
  const [isSubmitting, setIsSubmitting] = useState(false)

  const [formData, setFormData] = useState({
    building_name: '',
    floor: 1,
    room_number: '',
    description: '',
  })

  useEffect(() => {
    fetchLocations()
  }, [searchQuery])

  const fetchLocations = async () => {
    setLoading(true)
    try {
      const result = await getLocations({
        search: searchQuery,
        limit: 100,
      })
      if (result.success) {
        setLocations(result.data)
      }
    } catch (error) {
      console.error('Error fetching locations:', error)
      toast({
        title: 'Error',
        description: 'Failed to fetch locations',
        variant: 'destructive',
      })
    } finally {
      setLoading(false)
    }
  }

  const handleEdit = (location: Location) => {
    setSelectedLocation(location)
    setFormData({
      building_name: location.building_name,
      floor: location.floor,
      room_number: location.room_number,
      description: location.description,
    })
    setIsEditOpen(true)
  }

  const handleDelete = (locationId: string) => {
    setDeleteId(locationId)
    setIsDeleteOpen(true)
  }

  const confirmDelete = async () => {
    if (!deleteId) return

    setIsSubmitting(true)
    try {
      const result = await deleteLocation(deleteId)
      
      if (result.success) {
        toast({
          title: 'Success',
          description: 'Location deleted successfully',
        })
        setIsDeleteOpen(false)
        setDeleteId(null)
        fetchLocations()
      } else {
        toast({
          title: 'Error',
          description: result.error || 'Failed to delete location',
          variant: 'destructive',
        })
      }
    } catch (error) {
      console.error('Error deleting location:', error)
      toast({
        title: 'Error',
        description: 'Failed to delete location',
        variant: 'destructive',
      })
    } finally {
      setIsSubmitting(false)
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!selectedLocation) return

    setIsSubmitting(true)
    try {
      const result = await updateLocation(selectedLocation.location_id, formData)
      
      if (result.success) {
        toast({
          title: 'Success',
          description: 'Location updated successfully',
        })
        setIsEditOpen(false)
        setSelectedLocation(null)
        fetchLocations()
      } else {
        toast({
          title: 'Error',
          description: result.error || 'Failed to update location',
          variant: 'destructive',
        })
      }
    } catch (error) {
      console.error('Error updating location:', error)
      toast({
        title: 'Error',
        description: 'Failed to update location',
        variant: 'destructive',
      })
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Customer Locations</h1>
        <p className="text-muted-foreground">Manage customer locations (Read, Update, Delete only)</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Locations List</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="mb-4">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground h-4 w-4" />
              <Input
                type="text"
                placeholder="Search by building name, room number, or description..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-10"
              />
            </div>
          </div>

          {loading ? (
            <div className="text-center py-8">Loading...</div>
          ) : (
            <div className="rounded-md border overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Customer</TableHead>
                    <TableHead>Building Name</TableHead>
                    <TableHead>Floor</TableHead>
                    <TableHead>Room Number</TableHead>
                    <TableHead>Description</TableHead>
                    <TableHead>Phone</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {locations.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={7} className="text-center">
                        No locations found
                      </TableCell>
                    </TableRow>
                  ) : (
                    locations.map((location) => (
                      <TableRow key={location.location_id}>
                        <TableCell className="font-medium">
                          {location.customers ? (
                            <div className="text-sm">
                              <div className="font-medium">{location.customers.customer_name}</div>
                              {location.customers.primary_contact_person && (
                                <div className="text-muted-foreground">PIC: {location.customers.primary_contact_person}</div>
                              )}
                              {location.customers.email && (
                                <div className="text-muted-foreground text-xs">{location.customers.email}</div>
                              )}
                            </div>
                          ) : (
                            <div className="text-muted-foreground text-sm">No customer assigned</div>
                          )}
                        </TableCell>
                        <TableCell>{location.building_name}</TableCell>
                        <TableCell>{location.floor}</TableCell>
                        <TableCell>{location.room_number}</TableCell>
                        <TableCell>{location.description || '-'}</TableCell>
                        <TableCell>
                          {location.customers?.phone_number ? (
                            <div className="text-sm font-mono">{location.customers.phone_number}</div>
                          ) : (
                            <div className="text-muted-foreground text-sm">-</div>
                          )}
                        </TableCell>
                        <TableCell className="text-right">
                          <div className="flex gap-2 justify-end">
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => handleEdit(location)}
                            >
                              <Edit className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => handleDelete(location.location_id)}
                            >
                              <Trash2 className="h-4 w-4 text-destructive" />
                            </Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Edit Sheet */}
      <Sheet open={isEditOpen} onOpenChange={setIsEditOpen}>
        <SheetContent className="overflow-y-auto">
          <SheetHeader>
            <SheetTitle>Edit Location</SheetTitle>
            <SheetDescription>
              Update location information
            </SheetDescription>
          </SheetHeader>
          <form onSubmit={handleSubmit} className="space-y-4 mt-4">
            <div className="space-y-2">
              <Label htmlFor="building_name">Building Name *</Label>
              <Input
                id="building_name"
                value={formData.building_name}
                onChange={(e) => setFormData({ ...formData, building_name: e.target.value })}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="floor">Floor *</Label>
              <Input
                id="floor"
                type="number"
                value={formData.floor}
                onChange={(e) => setFormData({ ...formData, floor: parseInt(e.target.value) || 1 })}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="room_number">Room Number *</Label>
              <Input
                id="room_number"
                value={formData.room_number}
                onChange={(e) => setFormData({ ...formData, room_number: e.target.value })}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="description">Description</Label>
              <Input
                id="description"
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              />
            </div>
            <div className="flex gap-2 pt-4">
              <Button
                type="submit"
                disabled={isSubmitting}
                className="flex-1"
              >
                {isSubmitting ? 'Updating...' : 'Update Location'}
              </Button>
              <Button
                type="button"
                variant="outline"
                onClick={() => setIsEditOpen(false)}
                className="flex-1"
              >
                Cancel
              </Button>
            </div>
          </form>
        </SheetContent>
      </Sheet>

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={isDeleteOpen} onOpenChange={setIsDeleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Are you sure?</AlertDialogTitle>
            <AlertDialogDescription>
              This action cannot be undone. This will permanently delete the location
              from the database.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isSubmitting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={confirmDelete}
              disabled={isSubmitting}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {isSubmitting ? 'Deleting...' : 'Delete'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}
