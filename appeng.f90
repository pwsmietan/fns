From <@CEARN.cern.ch:METCALF@CERNVM.CERN.CH> Wed Dec 14 02:40:35 1994
Received: from CEARN.cern.ch (cearn.cern.ch [128.141.2.9]) by wcarchive.cdrom.com (8.6.8/8.6.6) with SMTP id CAA24413 for <nbridges@WCARCHIVE.CDROM.COM>; Wed, 14 Dec 1994 02:40:32 -0800
Message-Id: <199412141040.CAA24413@wcarchive.cdrom.com>
Received: from CERNVM.CERN.CH by CEARN.cern.ch (IBM VM SMTP V2R2)
   with BSMTP id 4081; Wed, 14 Dec 94 11:37:59 SET
Received: from CERNVM.CERN.CH (NJE origin METCALF@CERNVM) by CERNVM.CERN.CH
 (LMail V1.2a/1.8a) with BSMTP id 3446; Wed, 14 Dec 1994 11:39:25 +0100
Date:         Wed, 14 Dec 94 11:38:26 WET
From: Michael Metcalf <METCALF@crnvma.cern.ch>
Subject:      appeng.f90
To: nbridges@WCARCHIVE.CDROM.COM
Status: OR


module directory
!
! Strong typing imposed
   implicit none
!
! Only subroutine interfaces, the length of the character
! component, and the I/O unit number are public
   private
   public start, add_node, remove_node, retrieve,                              &
          dump_tree, restore_tree, finish
!
! Module constants
   character(*), parameter:: eot = 'End-of-Tree.....'
   integer, parameter, public :: unit = 4,   & ! I/O unit number
                                 max_char = 16 ! length of character component
!
! Define the basic tree type
   type node
       character(max_char) :: name    ! name of node
       real, pointer       :: y(:)    ! stored real data
       type(node), pointer :: parent  ! parent node
       type(node), pointer :: sibling ! next sibling node
       type(node), pointer :: child   ! first child node
   end type node
!
! Module variables
   type(node), pointer    :: current       ! current node
   type(node), pointer    :: forest_root   ! the root of the forest
   integer                :: max_data      ! max size of data array
   character(max_char), allocatable, target :: names(:)
                                           ! for returning list of names
! The module procedures

contains

   subroutine start
! Initialize the tree.
      allocate (forest_root)
      current => forest_root
      forest_root%name = 'forest_root'
      nullify(forest_root%parent, forest_root%sibling, forest_root%child)
      allocate(forest_root%y(0))
      max_data = 0
      allocate (names(0))
   end subroutine start
   subroutine find(name)
      character(*), intent(in) :: name
! Make the module variable current point to the node with given name,
! or be null if the name is not there.
      type(node), pointer    :: root
! For efficiency, we search the tree rooted at current, and if this
! fails try its parent and so on until the forest root is reached.
      if (associated(current)) then
         root => current
         nullify (current)
      else
         root => forest_root
      end if
      do
         call look(root)
         if (associated(current)) return
         root => root%parent
         if (.not.associated(root)) exit
      end do
   contains
      recursive subroutine look(root)
         type(node), intent(in), target :: root
! Look for name in the tree rooted at root. If found, make the
! module variable current point to the node
         type(node), pointer    :: child
!
         if (root%name == name) then
            current => root
         else
            child => root%child
            do
               if (.not.associated(child)) exit
               call look(child)
               if (associated(current)) return
               child => child%sibling
            end do
         end if
      end subroutine look
   end subroutine find
   subroutine add_node(name, name_of_parent, data)
      character(*), intent(in)   :: name, name_of_parent
! For a root, name = ''
      real, intent(in), optional :: data(:)
! Allocate a new tree node of type node, store the given name and
! data there, set pointers to the parent and to its next sibling
! (if any). If the parent is not found, the new node is treated as
! a root. It is assumed that the node is not already present in the
! forest.
      type(node), pointer :: new_node
!
      allocate (new_node)
      new_node%name = name
      if (present(data)) then
         allocate(new_node%y(size(data)))
         new_node%y = data
         max_data = max(max_data, size(data))
      else
         allocate(new_node%y(0))
      end if
!
! If name of parent is not null, search for it. If not found, print message.
      if (name_of_parent == '') then
         current => forest_root
      else
         call find (name_of_parent)
         if (.not.associated(current)) then
            print *, 'no parent ', name_of_parent, ' found for ', name
            current => forest_root
         end if
      end if
      new_node%parent => current
      new_node%sibling => current%child
      current%child => new_node
      nullify(new_node%child)
   end subroutine add_node

   subroutine remove_node(name)
      character(*), intent(in) :: name
! Remove node and the subtree rooted on it (if any),
! deallocating associated pointer targets.
      type(node), pointer :: parent, child, sibling
!
      call find (name)
      if (associated(current)) then
         parent =>  current%parent
         child => parent%child
         if (.not.associated(child, current)) then
! Make it the first child, looping through the siblings to find it
! and resetting the links
            parent%child => current
            sibling => child
            do
              if (associated (sibling%sibling, current)) exit
              sibling => sibling%sibling
            end do
            sibling%sibling => current%sibling
            current%sibling => child
         end if
         call remove(current)
      end if
   end subroutine remove_node
   recursive subroutine remove (old_node)
! Remove a first child node and the subtree rooted on it (if any),
! deallocating associated pointer targets.
      type(node), pointer :: old_node
      type(node), pointer :: child, sibling
!
      child => old_node%child
      do
         if (.not.associated(child)) exit
         sibling => child%sibling
         call remove(child)
         child => sibling
      end do
! remove leaf node
      if (associated(old_node%parent)) old_node%parent%child => old_node%sibling
      deallocate (old_node%y)
      deallocate (old_node)
   end subroutine remove

   subroutine retrieve(name, data, parent, children)
      character(*), intent(in)         :: name
      real, pointer                    :: data(:)
      character(max_char), intent(out) :: parent
      character(max_char), pointer     :: children(:)
! Returns a pointer to the data at the node, the name of the
! parent, and a pointer to the names of the children.
      integer count, i
      type(node), pointer :: child
!
      call find (name)
      if (associated(current)) then
         data => current%y
         parent = current%parent%name
! count the number of children
         count = 0
         child => current%child
         do
           if (.not.associated(child)) exit
           count = count + 1
           child => child%sibling
         end do
         deallocate (names)
         allocate (names(count))
! and store their names
         children => names
         child => current%child
         do i = 1, count
            children(i) = child%name
            child => child%sibling
         end do
      else
         nullify(data)
         parent = ''
         nullify(children)
      end if
   end subroutine retrieve
   subroutine dump_tree(root)
      character(*), intent(in) :: root
! Write out a complete tree followed by an end-of-tree record
! unformatted on the file unit.
      call find (root)
      if (associated(current)) then
         call out(current)
      end if
      write(unit) eot, 0, eot
   contains
      recursive subroutine out(root)
! Traverse a complete tree or subtree, writing out its contents
         type(node), intent(in) :: root     ! root node of tree
! Local variable
         type(node), pointer :: child
!
         write(unit) root%name, size(root%y), root%y, root%parent%name
         child => root%child
         do
            if (.not.associated(child)) exit
            call out (child)
            child => child%sibling
         end do
      end subroutine out
   end subroutine dump_tree

   subroutine restore_tree
! Reads a subtree unformatted from the file unit.
      character(max_char) :: name
      integer length_y
      real, allocatable   :: y(:)
      character(max_char) :: name_of_parent
!
      allocate(y(max_data))
      do
         read (unit) name, length_y, y(:length_y), name_of_parent
         if (name == eot) exit
         call add_node( name, name_of_parent, y(:length_y) )
      end do
      deallocate(y)
   end subroutine restore_tree

   subroutine finish
! Deallocate all allocated targets.
      call remove (forest_root)
      deallocate(names)
   end subroutine finish

end module directory
program test
   use directory
   implicit none
!
! Initialize a tree
   call start
! Fill it with some data
   call add_node('ernest','',(/1.,2./))
   call add_node('helen','ernest',(/3.,4.,5./))
   call add_node('douglas','ernest',(/6.,7./))
   call add_node('john','helen',(/8./))
   call add_node('betty','helen',(/9.,10./))
   call add_node('nigel','betty',(/11./))
   call add_node('peter','betty',(/12./))
   call add_node('ruth','betty')
! Manipulate subtrees
   open(unit, form='unformatted', status='scratch')
   call dump_tree('betty')
   call remove_node('betty')
   write(*,*); call print_tree('ernest')
   rewind unit
   call restore_tree
   rewind unit
   write(*,*); call print_tree('ernest')
   call dump_tree('john')
   call remove_node('john')
   write(*,*); call print_tree('ernest')
   rewind unit
   call restore_tree
   write(*,*); call print_tree('ernest')
! Return storage
   call finish

contains

   recursive subroutine print_tree(name)
! To print the data contained in a subtree
      character(*) :: name
      integer                             i
      real, pointer                    :: data(:)
      character(max_char)                 parent, self
      character(max_char), pointer     :: children(:)
      character(max_char), allocatable :: siblings(:)
!
      call retrieve(name, data, parent, children)
      if (.not.associated(data)) return
      self = name; write(*,*) self, data
      write(*,*) '   parent:   ', parent
      if (size(children) > 0 ) write(*,*) '   children: ', children
      allocate(siblings(size(children)))
      siblings = children
      do i = 1, size(children)
         call print_tree(siblings(i))
      end do
   end subroutine print_tree

end program test

