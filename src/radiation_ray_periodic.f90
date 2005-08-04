! $Id: radiation_ray_periodic.f90,v 1.21 2005-08-04 16:48:37 theine Exp $

!!!  NOTE: this routine will perhaps be renamed to radiation_feautrier
!!!  or it may be combined with radiation_ray.

!** AUTOMATIC CPARAM.INC GENERATION ****************************
! Declare (for generation of cparam.inc) the number of f array
! variables and auxiliary variables added by this module
!
! MVAR CONTRIBUTION 0
! MAUX CONTRIBUTION 1
!
!***************************************************************

module Radiation

!  Radiation (solves transfer equation along rays)
!  The direction of the ray is given by the vector (lrad,mrad,nrad),
!  and the parameters radx0,rady0,radz0 gives the maximum number of
!  steps of the direction vector in the corresponding direction.

  use Cparam
  use Messages
!
  implicit none
!
  include 'radiation.h'
!
  type Qbound !Qbc
    real :: val
    logical :: set
  endtype Qbound

  type Qpoint !Qpt
    real, pointer :: val
    logical, pointer :: set
  endtype Qpoint

  real, dimension (mx,my,mz) :: Srad,lnchi,tau,Qrad,Qrad0
  type (Qbound), dimension (my,mz), target :: Qbc_yz
  type (Qbound), dimension (mx,mz), target :: Qbc_zx
  type (Qbound), dimension (mx,my), target :: Qbc_xy
  type (Qpoint), dimension (my,mz) :: Qpt_yz
  type (Qpoint), dimension (mx,mz) :: Qpt_zx
  type (Qpoint), dimension (mx,my) :: Qpt_xy

  character (len=2*bclen+1), dimension(3) :: bc_rad=(/'0:0','0:0','S:0'/)
  character (len=bclen), dimension(3) :: bc_rad1,bc_rad2
  character (len=bclen) :: bc_ray_x,bc_ray_y,bc_ray_z
  integer, parameter :: maxdir=26
  integer, dimension (maxdir,3) :: dir
  real, dimension (maxdir) :: weight
  real :: arad
  real :: dtau_thresh1,dtau_thresh2
  integer :: lrad,mrad,nrad,rad2
  integer :: idir,ndir
  integer :: llstart,llstop,ll1,ll2,lsign
  integer :: mmstart,mmstop,mm1,mm2,msign
  integer :: nnstart,nnstop,nn1,nn2,nsign
  integer :: ipzstart,ipzstop
  logical :: lperiodic_ray,lperiodic_ray_x,lperiodic_ray_y,lperiodic_ray_z
  character (len=labellen) :: source_function_type='LTE',opacity_type='Hminus'
  real :: kappa_cst=1.0
  real :: Srad_const=1.0,amplSrad=1.0,radius_Srad=1.0
  real :: kx_Srad=0.0,ky_Srad=0.0,kz_Srad=0.0
  real :: lnchi_const=1.0,ampllnchi=1.0,radius_lnchi=1.0
  real :: kx_lnchi=0.0,ky_lnchi=0.0,kz_lnchi=0.0
  integer :: nrad_rep=1 ! for timings
!
!  Default values for one pair of vertical rays
!
  integer :: radx=0,rady=0,radz=1,rad2max=1
!
  logical :: lcooling=.true.,lrad_debug=.false.,lrad_timing=.false.
  logical :: lintrinsic=.true.,lcommunicate=.true.,lrevision=.true.

  character :: lrad_str,mrad_str,nrad_str
  character(len=3) :: raydir_str
!
!  Definition of dummy variables for FLD routine
!
  real :: DFF_new=0.  !(dum)
  integer :: idiag_frms=0,idiag_fmax=0,idiag_Erad_rms=0,idiag_Erad_max=0
  integer :: idiag_Egas_rms=0,idiag_Egas_max=0,idiag_Qradrms=0,idiag_Qradmax=0

  namelist /radiation_init_pars/ &
       radx,rady,radz,rad2max,bc_rad,lrad_debug,kappa_cst, &
       source_function_type,opacity_type, &
       Srad_const,amplSrad,radius_Srad,lrad_timing, &
       kx_Srad,ky_Srad,kz_Srad,kx_lnchi,ky_lnchi,kz_lnchi, &
       lnchi_const,ampllnchi,radius_lnchi, &
       lintrinsic,lcommunicate,lrevision,nrad_rep

  namelist /radiation_run_pars/ &
       radx,rady,radz,rad2max,bc_rad,lrad_debug,kappa_cst, &
       source_function_type,opacity_type, &
       Srad_const,amplSrad,radius_Srad,lrad_timing, &
       kx_Srad,ky_Srad,kz_Srad,kx_lnchi,ky_lnchi,kz_lnchi, &
       lnchi_const,ampllnchi,radius_lnchi, &
       lintrinsic,lcommunicate,lrevision,lcooling,nrad_rep

  contains

!***********************************************************************
    subroutine register_radiation()
!
!  Initialize radiation flags
!
!  24-mar-03/axel+tobi: coded
!
      use Cdata, only: iQrad,nvar,naux,aux_var,aux_count,lroot,varname
      use Cdata, only: lradiation,lradiation_ray
      use Mpicomm, only: stop_it
!
      logical, save :: first=.true.
!
      if (first) then
        first = .false.
      else
        call stop_it('register_radiation called twice')
      endif
!
      lradiation=.true.
      lradiation_ray=.true.
!
!  Set indices for auxiliary variables
!
      iQrad = mvar + naux +1; naux = naux + 1
!
      if ((ip<=8) .and. lroot) then
        print*, 'register_radiation: radiation naux = ', naux
        print*, 'iQrad = ', iQrad
      endif
!
!  Put variable name in array
!
      varname(iQrad) = 'Qrad'
!
!  Identify version number (generated automatically by CVS)
!
      if (lroot) call cvs_id( &
           "$Id: radiation_ray_periodic.f90,v 1.21 2005-08-04 16:48:37 theine Exp $")
!
!  Check that we aren't registering too many auxilary variables
!
      if (nvar > mvar) then
        if (lroot) write(0,*) 'naux = ', naux, ', maux = ', maux
        call stop_it('register_radiation: naux > maux')
      endif
!
!  Writing files for use with IDL
!
      if (naux < maux) aux_var(aux_count)=',Qrad $'
      if (naux == maux) aux_var(aux_count)=',Qrad'
      aux_count=aux_count+1
      if (lroot) write(15,*) 'Qrad = fltarr(mx,my,mz)*one'
!
    endsubroutine register_radiation
!***********************************************************************
    subroutine initialize_radiation()
!
!  Calculate number of directions of rays
!  Do this in the beginning of each run
!
!  16-jun-03/axel+tobi: coded
!  03-jul-03/tobi: position array added
!
      use Cdata, only: lroot,sigmaSB,pi,datadir
      use Sub, only: parse_bc_rad
      use Mpicomm, only: stop_it
!
!  Check that the number of rays does not exceed maximum
!
      if (radx>1) call stop_it("radx currently must not be greater than 1")
      if (rady>1) call stop_it("rady currently must not be greater than 1")
      if (radz>1) call stop_it("radz currently must not be greater than 1")
!
!  Count
!
      idir=1

      do nrad=-radz,radz
      do mrad=-rady,rady
      do lrad=-radx,radx
        rad2=lrad**2+mrad**2+nrad**2
        if ((rad2>0.and.rad2<=rad2max).and..not.(rad2==2.and.nrad==0)) then 
          dir(idir,1)=lrad
          dir(idir,2)=mrad
          dir(idir,3)=nrad
          idir=idir+1
        endif
      enddo
      enddo
      enddo
!
!  Total number of directions
!
      ndir=idir-1
!
!  Determine when terms like  exp(-dtau)-1  are to be evaluated
!  as a power series 
!
!  Experimentally determined optimum
!  Relative errors for (emdtau1, emdtau2) will be
!  (1e-6, 1.5e-4) for floats and (3e-13, 1e-8) for doubles
!
      dtau_thresh1=-log(epsilon(dtau_thresh1))
      dtau_thresh2=1.6*epsilon(dtau_thresh2)**0.25
!
!  Calculate arad for LTE source function
!
      arad=SigmaSB/pi
!
!  Calculate weights
!
      weight=1.0/ndir
!
      if (lroot.and.ip<14) print*,'initialize_radiation: ndir =',ndir
!
!  Check boundary conditions
!
      if (lroot.and.ip<14) print*,'initialize_radiation: bc_rad =',bc_rad
!
      call parse_bc_rad(bc_rad,bc_rad1,bc_rad2)
!
    endsubroutine initialize_radiation
!***********************************************************************
    subroutine radtransfer(f)
!
!  Integration of the radiative transfer equation along rays
!
!  16-jun-03/axel+tobi: coded
!
      use Cdata, only: ldebug,headt,iQrad
      use Mpicomm, only: mpiwtime,lroot
      use Mpicomm, only: mpireduce_sum, mpireduce_min, mpireduce_max
!
      real, dimension(mx,my,mz,mvar+maux) :: f
!
!  Identifier
!
      if (ldebug.and.headt) print*,'radtransfer'
!
!  Calculate source function and opacity
!
      call source_function(f)
      call opacity(f)
!
!  Initialize heating rate
!
      f(:,:,:,iQrad)=0
!
!  Loop over directions ``in the upper half room'' (nrad==1)
!
      do idir=1,ndir

        call raydirection

        if (lintrinsic) call Qintrinsic

        if (lcommunicate) then
          if (lperiodic_ray) then
            call Qperiodic
          else
            call Qassign_pointers
            call Qcommunicate
          endif
        endif

        if (lrevision) call Qrevision

        f(:,:,:,iQrad)=f(:,:,:,iQrad)+weight(idir)*Qrad

      enddo

    endsubroutine radtransfer
!***********************************************************************
    subroutine raydirection
!
!  Determine certain variables depending on the ray direction
!
!  10-nov-03/tobi: coded
!
      use Cdata, only: ldebug,headt

      integer :: l,m,n
!
!  Identifier
!
      if(ldebug.and.headt) print*,'raydirection'
!
!  Get direction components
!
      lrad=dir(idir,1)
      mrad=dir(idir,2)
      nrad=dir(idir,3)
!
!  Determine start and stop positions
!
      llstart=l1; llstop=l2; ll1=l1; ll2=l2; lsign=+1
      mmstart=m1; mmstop=m2; mm1=m1; mm2=m2; msign=+1
      nnstart=n1; nnstop=n2; nn1=n1; nn2=n2; nsign=+1
      if (lrad>0) then; llstart=l1; llstop=l2; ll1=l1-lrad; lsign=+1; endif
      if (lrad<0) then; llstart=l2; llstop=l1; ll2=l2-lrad; lsign=-1; endif
      if (mrad>0) then; mmstart=m1; mmstop=m2; mm1=m1-mrad; msign=+1; endif
      if (mrad<0) then; mmstart=m2; mmstop=m1; mm2=m2-mrad; msign=-1; endif
      if (nrad>0) then; nnstart=n1; nnstop=n2; nn1=n1-nrad; nsign=+1; endif
      if (nrad<0) then; nnstart=n2; nnstop=n1; nn2=n2-nrad; nsign=-1; endif
!
!  Are we dealing with a periodic ray?
!
      lperiodic_ray_x=(lrad/=0.and.mrad==0.and.nrad==0)
      lperiodic_ray_y=(lrad==0.and.mrad/=0.and.nrad==0)
      lperiodic_ray=(lperiodic_ray_x.or.lperiodic_ray_y)
!
!  Determine boundary conditions
!
      if (nrad>0) bc_ray_z=bc_rad1(3)
      if (nrad<0) bc_ray_z=bc_rad2(3)
!
!  Determine start and stop processors
!
      if (nrad>0) then; ipzstart=0; ipzstop=nprocz-1; endif
      if (nrad<0) then; ipzstart=nprocz-1; ipzstop=0; endif
!
!  Label for debug output
!
      if (lrad_debug) then
        lrad_str='0'; mrad_str='0'; nrad_str='0'
        if (lrad>0) lrad_str='p'
        if (lrad<0) lrad_str='m'
        if (mrad>0) mrad_str='p'
        if (mrad<0) mrad_str='m'
        if (nrad>0) nrad_str='p'
        if (nrad<0) nrad_str='m'
        raydir_str=lrad_str//mrad_str//nrad_str
      endif

    endsubroutine raydirection
!***********************************************************************
    subroutine Qintrinsic
!
!  Integration radiation transfer equation along rays
!
!  This routine is called before the communication part
!  All rays start with zero intensity
!
!  16-jun-03/axel+tobi: coded
!   3-aug-03/axel: added max(dtau,dtaumin) construct
!
      use Cdata, only: ldebug,headt,dx,dy,dz,directory_snap
      use IO, only: output
!
      real :: Srad1st,Srad2nd,dlength,emdtau1,emdtau2,emdtau
      real :: dtau_m,dtau_p,dSdtau_m,dSdtau_p
      integer :: l,m,n
      character(len=3) :: raydir
!
!  identifier
!
      if(ldebug.and.headt) print*,'Qintrinsic'
!
!  line elements
!
      dlength=sqrt((dx*lrad)**2+(dy*mrad)**2+(dz*nrad)**2)
!
!  set optical depth and intensity initially to zero
!
      tau=0
      Qrad=0
!
!  loop over all meshpoints
!
      do n=nnstart,nnstop,nsign
      do m=mmstart,mmstop,msign
      do l=llstart,llstop,lsign 

        dtau_m=sqrt(exp(lnchi(l-lrad,m-mrad,n-nrad)+lnchi(l,m,n)))*dlength
        dtau_p=sqrt(exp(lnchi(l,m,n)+lnchi(l+lrad,m+mrad,n+nrad)))*dlength
        dSdtau_m=(Srad(l,m,n)-Srad(l-lrad,m-mrad,n-nrad))/dtau_m
        dSdtau_p=(Srad(l+lrad,m+mrad,n+nrad)-Srad(l,m,n))/dtau_p
        Srad1st=(dSdtau_p*dtau_m+dSdtau_m*dtau_p)/(dtau_m+dtau_p)
        Srad2nd=2*(dSdtau_p-dSdtau_m)/(dtau_m+dtau_p)
        if (dtau_m>dtau_thresh1) then
          emdtau=0.0
          emdtau1=1.0
          emdtau2=-1.0
        elseif (dtau_m<dtau_thresh2) then
          emdtau1=dtau_m*(1-0.5*dtau_m*(1-0.33333333*dtau_m))
          emdtau=1-emdtau1
          emdtau2=-dtau_m**2*(0.5+0.33333333*dtau_m)
        else
          emdtau=exp(-dtau_m)
          emdtau1=1-emdtau
          emdtau2=emdtau*(1+dtau_m)-1
        endif
        tau(l,m,n)=tau(l-lrad,m-mrad,n-nrad)+dtau_m
        Qrad(l,m,n)=Qrad(l-lrad,m-mrad,n-nrad)*emdtau &
                   -Srad1st*emdtau1-Srad2nd*emdtau2

      enddo
      enddo
      enddo
!
!  debug output
!
      if (lrad_debug) then
        call output(trim(directory_snap)//'/tau-'//raydir_str//'.dat',tau,1)
        call output(trim(directory_snap)//'/Qintr-'//raydir_str//'.dat',Qrad,1)
      endif
!
    endsubroutine Qintrinsic
!***********************************************************************
    subroutine Qassign_pointers
!
!  For each gridpoint at the downstream boundaries, set up a
!  pointer (Qpt_{yz,zx,xy}) that points to a unique location
!  at the upstream boundaries (Qbc_{yz,zx,xy}). Both
!  Qpt_{yz,zx,xy} and Qbc_{yz,zx,xy} are derived types
!  containing at each grid point the value of the heating rate
!  (...%val) and whether the heating rate at that point has
!  been already set or not (...%set).
!
!  30-jul-05/tobi: coded
!
      integer :: l,m,n
      integer :: steps
      integer :: minsteps
      integer :: lsteps,msteps,nsteps
!
!  yz-plane
!
      if (lrad/=0) then

           l=llstop
        do m=mm1,mm2
        do n=nn1,nn2

          steps=(l+lrad-llstart)/lrad
          minsteps=1

          if (mrad/=0) then
            msteps=(m+mrad-mmstart)/mrad
            if (msteps<steps) then
              steps=msteps
              minsteps=2
            endif
          endif

          if (nrad/=0) then
            nsteps=(n+nrad-nnstart)/nrad
            if (nsteps<steps) then
              steps=nsteps
              minsteps=3
            endif
          endif

          select case (minsteps)
            case (1)
              Qpt_yz(m,n)%val => Qbc_yz(m-mrad*steps,n-nrad*steps)%val
              Qpt_yz(m,n)%set => Qbc_yz(m-mrad*steps,n-nrad*steps)%set
            case (2)
              Qpt_yz(m,n)%val => Qbc_zx(l-lrad*steps,n-nrad*steps)%val
              Qpt_yz(m,n)%set => Qbc_zx(l-lrad*steps,n-nrad*steps)%set
            case (3)
              Qpt_yz(m,n)%val => Qbc_xy(l-lrad*steps,m-mrad*steps)%val
              Qpt_yz(m,n)%set => Qbc_xy(l-lrad*steps,m-mrad*steps)%set
          endselect

        enddo
        enddo

      endif
!
!  zx-plane
!
      if (mrad/=0) then

           m=mmstop
        do n=nn1,nn2
        do l=ll1,ll2

          steps=(m+mrad-mmstart)/mrad
          minsteps=2

          if (nrad/=0) then
            nsteps=(n+nrad-nnstart)/nrad
            if (nsteps<steps) then
              steps=nsteps
              minsteps=3
            endif
          endif

          if (lrad/=0) then
            lsteps=(l+lrad-llstart)/lrad
            if (lsteps<steps) then
              steps=lsteps
              minsteps=1
            endif
          endif

          select case (minsteps)
            case (1)
              Qpt_zx(l,n)%val => Qbc_yz(m-mrad*steps,n-nrad*steps)%val
              Qpt_zx(l,n)%set => Qbc_yz(m-mrad*steps,n-nrad*steps)%set
            case (2)
              Qpt_zx(l,n)%val => Qbc_zx(l-lrad*steps,n-nrad*steps)%val
              Qpt_zx(l,n)%set => Qbc_zx(l-lrad*steps,n-nrad*steps)%set
            case (3)
              Qpt_zx(l,n)%val => Qbc_xy(l-lrad*steps,m-mrad*steps)%val
              Qpt_zx(l,n)%set => Qbc_xy(l-lrad*steps,m-mrad*steps)%set
          endselect

        enddo
        enddo

      endif
!
!  xy-plane
!
      if (nrad/=0) then

           n=nnstop
        do l=ll1,ll2
        do m=mm1,mm2

          steps=(n+nrad-nnstart)/nrad
          minsteps=3

          if (lrad/=0) then
            lsteps=(l+lrad-llstart)/lrad
            if (lsteps<steps) then
              steps=lsteps
              minsteps=1
            endif
          endif

          if (mrad/=0) then
            msteps=(m+mrad-mmstart)/mrad
            if (msteps<steps) then
              steps=msteps
              minsteps=2
            endif
          endif

          select case (minsteps)
            case (1)
              Qpt_xy(l,m)%val => Qbc_yz(m-mrad*steps,n-nrad*steps)%val
              Qpt_xy(l,m)%set => Qbc_yz(m-mrad*steps,n-nrad*steps)%set
            case (2)
              Qpt_xy(l,m)%val => Qbc_zx(l-lrad*steps,n-nrad*steps)%val
              Qpt_xy(l,m)%set => Qbc_zx(l-lrad*steps,n-nrad*steps)%set
            case (3)
              Qpt_xy(l,m)%val => Qbc_xy(l-lrad*steps,m-mrad*steps)%val
              Qpt_xy(l,m)%set => Qbc_xy(l-lrad*steps,m-mrad*steps)%set
          endselect

        enddo
        enddo

      endif

    endsubroutine Qassign_pointers
!***********************************************************************
    subroutine Qcommunicate
!
!  Determine the boundary heating rates at all upstream boundaries.
!
!  First the boundary heating rates at the non-periodic xy-boundary 
!  are set either through the boundary condition for the entire
!  computational domain (ipz==ipzstart) or through communication with
!  the neighboring processor in the upstream z-direction (ipz/=ipzstart).
!
!  The boundary heating rates at the periodic yz- and zx-boundaries
!  are then obtained by repetitive communication along the y-direction
!  until both boundaries are entirely set with the correct values.
!
!  30-jul-05/tobi: coded
!
      use Cdata, only: ipz
      use Mpicomm, only: radboundary_xy_recv,radboundary_xy_send
      use Mpicomm, only: radboundary_zx_sendrecv

      real, dimension (my,mz) :: emtau_yz,Qrad_yz
      real, dimension (mx,mz) :: emtau_zx,Qrad_zx
      real, dimension (mx,my) :: emtau_xy,Qrad_xy
      real, dimension (mx,mz) :: Qsend_zx,Qrecv_zx
      real, dimension (mx,my) :: Qrecv_xy,Qsend_xy

      integer :: l,m,n
      logical :: all_yz,all_zx
!
!  Initially no boundaries are set
!
      Qbc_xy%set=.false.
      Qbc_yz%set=.false.
      Qbc_zx%set=.false.

      all_yz=.false.
      all_zx=.false.
!
!  either receive or set xy-boundary heating rate
!
      if (ipz==ipzstart) then
        call radboundary_xy_set(Qrecv_xy)
      else
        call radboundary_xy_recv(nrad,idir,Qrecv_xy)
      endif
!
!  copy the above heating rates to the xy-target arrays which are then set
!
      Qbc_xy(ll1:ll2,mm1:mm2)%val = Qrecv_xy(ll1:ll2,mm1:mm2)
      Qbc_xy(ll1:ll2,mm1:mm2)%set = .true.
!
!  do the same for the yz- and zx-target arrays where those boundaries
!  overlap with the xy-boundary and calculate exp(-tau) and Qrad at the
!  downstream boundaries.
!
      if (lrad/=0) then

        Qbc_yz(mm1:mm2,nnstart-nrad)%val = Qrecv_xy(llstart-lrad,mm1:mm2)
        Qbc_yz(mm1:mm2,nnstart-nrad)%set = .true.

        emtau_yz(mm1:mm2,nn1:nn2) = exp(-tau(llstop,mm1:mm2,nn1:nn2))
         Qrad_yz(mm1:mm2,nn1:nn2) =     Qrad(llstop,mm1:mm2,nn1:nn2)

      else

        all_yz=.true.

      endif

      if (mrad/=0) then

        Qbc_zx(ll1:ll2,nnstart-nrad)%val = Qrecv_xy(ll1:ll2,mmstart-mrad)
        Qbc_zx(ll1:ll2,nnstart-nrad)%set = .true.

        emtau_zx(ll1:ll2,nn1:nn2) = exp(-tau(ll1:ll2,mmstop,nn1:nn2))
         Qrad_zx(ll1:ll2,nn1:nn2) =     Qrad(ll1:ll2,mmstop,nn1:nn2)

      else

        all_zx=.true.

      endif
!
!  communicate along the y-direction until all upstream heating rates at
!  the yz- and zx-boundaries are determined.
!
      if (lrad/=0.or.mrad/=0) then; do

        if (lrad/=0.and..not.all_yz) then

          forall (m=mm1:mm2,n=nn1:nn2,Qpt_yz(m,n)%set.and..not.Qbc_yz(m,n)%set)

            Qbc_yz(m,n)%val = Qpt_yz(m,n)%val*emtau_yz(m,n)+Qrad_yz(m,n)
            Qbc_yz(m,n)%set = Qpt_yz(m,n)%set

          endforall

          all_yz=all(Qbc_yz(mm1:mm2,nn1:nn2)%set)

          if (all_yz.and.all_zx) exit

        endif

        if (mrad/=0.and..not.all_zx) then

          forall (l=ll1:ll2,n=nn1:nn2,Qpt_zx(l,n)%set.and..not.Qbc_zx(l,n)%set)

            Qsend_zx(l,n) = Qpt_zx(l,n)%val*emtau_zx(l,n)+Qrad_zx(l,n)

          endforall

          if (nprocy>1) then
            call radboundary_zx_sendrecv(mrad,idir,Qsend_zx,Qrecv_zx)
          endif

          forall (l=ll1:ll2,n=nn1:nn2,Qpt_zx(l,n)%set.and..not.Qbc_zx(l,n)%set)

            Qbc_zx(l,n)%val = Qrecv_zx(l,n)
            Qbc_zx(l,n)%set = Qpt_zx(l,n)%set

          endforall

          all_zx=all(Qbc_zx(ll1:ll2,nn1:nn2)%set)

          if (all_yz.and.all_zx) exit

        endif

      enddo; endif
!
!  copy all heating rates at the upstream boundaries to the Qrad0 which
!  is used in Qrevision below.
!
      if (lrad/=0) then
        Qrad0(llstart-lrad,mm1:mm2,nn1:nn2)=Qbc_yz(mm1:mm2,nn1:nn2)%val
      endif

      if (mrad/=0) then
        Qrad0(ll1:ll2,mmstart-mrad,nn1:nn2)=Qbc_zx(ll1:ll2,nn1:nn2)%val
      endif

      if (nrad/=0) then
        Qrad0(ll1:ll2,mm1:mm2,nnstart-nrad)=Qbc_xy(ll1:ll2,mm1:mm2)%val
      endif
!
!  If this is not the last processor in ray direction (z-component) then
!  calculate the downstream heating rates at the xy-boundary and send them
!  to the next processor.
!
      if (ipz/=ipzstop) then

        forall (l=ll1:ll2,m=mm1:mm2)

          emtau_xy(l,m) = exp(-tau(l,m,nnstop))
          Qrad_xy(l,m) = Qrad(l,m,nnstop)
          Qsend_xy(l,m) = Qpt_xy(l,m)%val*emtau_xy(l,m)+Qrad_xy(l,m)

        endforall

        call radboundary_xy_send(nrad,idir,Qsend_xy)

      endif

    endsubroutine Qcommunicate
!***********************************************************************
    subroutine Qperiodic
!
!  DOCUMENT ME!
!
      use Cdata, only: ipy,iproc
      use Mpicomm, only: radboundary_zx_periodic_ray
      use IO, only: output

      real, dimension(ny,nz) :: Qrad_yz,tau_yz,emtau1_yz
      real, dimension(nx,nz) :: Qrad_zx,tau_zx,emtau1_zx
      real, dimension(nx,nz) :: Qrad_tot_zx,tau_tot_zx,emtau1_tot_zx
      real, dimension(nx,nz,0:nprocy-1) :: Qrad_zx_all,tau_zx_all
      integer :: l,m,n
      integer :: ipystart,ipystop,ipm
!
!  x-direction
!
      if (lrad/=0) then
  !
  !  Intrinsic heating rate and optical depth at the downstream boundary.
  !
        Qrad_yz=Qrad(llstop,m1:m2,n1:n2)
        tau_yz=tau(llstop,m1:m2,n1:n2)
  !
  !  Try to avoid time consuming exponentials and loss of precision.
  !
        where (tau_yz>dtau_thresh1)
          emtau1_yz=1.0
        elsewhere (tau_yz<dtau_thresh2)
          emtau1_yz=tau_yz*(1-0.5*tau_yz*(1-0.33333333*tau_yz))
        elsewhere
          emtau1_yz=1-exp(-tau_yz)
        endwhere
  !
  !  The requirement of periodicity gives the following heating rate at the
  !  upstream boundary.
  !
        Qrad0(llstart-lrad,m1:m2,n1:n2)=Qrad_yz/emtau1_yz

      endif
!
!  y-direction
!
      if (mrad/=0) then
  !
  !  Intrinsic heating rate and optical depth at the downstream boundary of
  !  each processor.
  !
        Qrad_zx=Qrad(l1:l2,mmstop,n1:n2)
        tau_zx=tau(l1:l2,mmstop,n1:n2)
  !
  !  Gather intrinsic heating rates and optical depths from all processors
  !  into one rank-3 array available on each processor.
  !
        call radboundary_zx_periodic_ray(Qrad_zx,tau_zx,Qrad_zx_all,tau_zx_all)
  !
  !  Find out in which direction we want to loop over processors.
  !
        if (mrad>0) then; ipystart=0; ipystop=nprocy-1; endif
        if (mrad<0) then; ipystart=nprocy-1; ipystop=0; endif
  !
  !  We need the sum of all intrinsic optical depths and the attenuated sum of
  !  all intrinsic heating rates. The latter needs to be summed in the
  !  downstream direction starting at the current processor. Set both to zero
  !  initially.
  !
        Qrad_tot_zx=0.0
        tau_tot_zx=0.0
  !
  !  Do the sum from the this processor to the last one in the downstream
  !  direction.
  !
        do ipm=ipy,ipystop,msign
          Qrad_tot_zx=Qrad_tot_zx*exp(-tau_zx_all(:,:,ipm))+Qrad_zx_all(:,:,ipm)
          tau_tot_zx=tau_tot_zx+tau_zx_all(:,:,ipm)
        enddo
  !
  !  Do the sum from the first processor in the upstream direction to the one
  !  before this one.
  !
        do ipm=ipystart,ipy-msign,msign
          Qrad_tot_zx=Qrad_tot_zx*exp(-tau_zx_all(:,:,ipm))+Qrad_zx_all(:,:,ipm)
          tau_tot_zx=tau_tot_zx+tau_zx_all(:,:,ipm)
        enddo
  !
  !  To calculate the boundary heating rate we need to compute an exponential
  !  term involving the total optical depths across all processors.
  !  Try to avoid time consuming exponentials and loss of precision.
  !
        where (tau_tot_zx>dtau_thresh1)
          emtau1_tot_zx=1.0
        elsewhere (tau_tot_zx<dtau_thresh2)
          emtau1_tot_zx=tau_tot_zx*(1-0.5*tau_tot_zx*(1-0.33333333*tau_tot_zx))
        elsewhere 
          emtau1_tot_zx=1-exp(-tau_tot_zx)
        endwhere
  !
  !  The requirement of periodicity gives the following heating rate at the
  !  upstream boundary of this processor.
  !
        Qrad0(l1:l2,mmstart-mrad,n1:n2)=Qrad_tot_zx/emtau1_tot_zx

      endif

    endsubroutine Qperiodic
!***********************************************************************
    subroutine Qrevision
!
!  This routine is called after the communication part
!  The true boundary intensities I0 are now known and
!  the correction term I0*exp(-tau) is added
!
!  16-jun-03/axel+tobi: coded
!
      use Cdata, only: ldebug,headt,directory_snap
      use Slices, only: Isurf_xy
      use IO, only: output
!
      integer :: l,m,n
!
!  identifier
!
      if(ldebug.and.headt) print*,'Qrevision'
!
!  do the ray...
!
      do n=nnstart,nnstop,nsign
      do m=mmstart,mmstop,msign
      do l=llstart,llstop,lsign
          Qrad0(l,m,n)=Qrad0(l-lrad,m-mrad,n-nrad)
          Qrad(l,m,n)=Qrad(l,m,n)+Qrad0(l,m,n)*exp(-tau(l,m,n))
      enddo
      enddo
      enddo
!
!  calculate surface intensity for upward rays
!
      if (lrad==0.and.mrad==0.and.nrad==1) then
        Isurf_xy=Qrad(l1:l2,m1:m2,nnstop)+Srad(l1:l2,m1:m2,nnstop)
      endif
!
      if (lrad_debug) then
        call output(trim(directory_snap)//'/Qrev-'//raydir_str//'.dat',Qrad,1)
      endif
!
    endsubroutine Qrevision
!***********************************************************************
    subroutine radboundary_xy_set(Qrad0_xy)
!
!  Sets the physical boundary condition on xy plane
!
!  6-jul-03/axel+tobi: coded
!
      use Mpicomm, only: stop_it
!
      real, dimension(mx,my) :: Qrad0_xy
!
!  No incoming intensity
!
      if (bc_ray_z=='0') then
        Qrad0_xy=-Srad(:,:,nnstart-nrad)
      endif
!
!  Set intensity equal to source function
!
      if (bc_ray_z=='S') then
        Qrad0_xy=0
      endif
!
    endsubroutine radboundary_xy_set
!***********************************************************************
    subroutine radiative_cooling(f,df,p)
!
!  calculate source function
!
!  25-mar-03/axel+tobi: coded
!
      use Cdata
      use Sub
      use EquationOfState
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,mvar) :: df
      type (pencil_case) :: p
      real, dimension (nx) :: Qrad,Qrad2
!
      Qrad=f(l1:l2,m,n,iQrad)
!
!  Add radiative cooling
!
      if (lcooling) then
        df(l1:l2,m,n,iss)=df(l1:l2,m,n,iss) &
                         +4*pi*exp(lnchi(l1:l2,m,n)-p%lnrho)*p%TT1*Qrad
      endif
!
!  diagnostics
!
      if (ldiagnos) then
        Qrad2=f(l1:l2,m,n,iQrad)**2
        if(idiag_Qradrms/=0) call sum_mn_name(Qrad2,idiag_Qradrms,lsqrt=.true.)
        if(idiag_Qradmax/=0) call max_mn_name(Qrad2,idiag_Qradmax,lsqrt=.true.)
      endif
!
    endsubroutine radiative_cooling
!***********************************************************************
    subroutine source_function(f)
!
!  calculates source function
!
!  03-apr-04/tobi: coded
!
      use Cdata, only: m,n,x,y,z,Lx,Ly,Lz,pi,dx,dy,dz,pi,directory_snap
      use Mpicomm, only: stop_it
      use EquationOfState, only: eoscalc
      use IO, only: output

      real, dimension(mx,my,mz,mvar+maux), intent(in) :: f
      real, dimension(mx) :: lnTT
      logical, save :: lfirst=.true.

      select case (source_function_type)

      case ('LTE')
        do n=1,mz
        do m=1,my
          call eoscalc(f,mx,lnTT=lnTT)
          Srad(:,m,n)=arad*exp(4*lnTT)
        enddo
        enddo

      case ('blob')
        if (lfirst) then
          Srad=Srad_const &
              +amplSrad*spread(spread(exp(-(x/radius_Srad)**2),2,my),3,mz) &
                       *spread(spread(exp(-(y/radius_Srad)**2),1,mx),3,mz) &
                       *spread(spread(exp(-(z/radius_Srad)**2),1,mx),2,my)
          lfirst=.false.
        endif

      case ('cos')
        if (lfirst) then
          Srad=Srad_const &
              +amplSrad*spread(spread(cos(kx_Srad*x),2,my),3,mz) &
                       *spread(spread(cos(ky_Srad*y),1,mx),3,mz) &
                       *spread(spread(cos(kz_Srad*z),1,mx),2,my)
          lfirst=.false.
        endif

      case default
        call stop_it('no such source function type: '//&
                     trim(source_function_type))

      end select

      if (lrad_debug) then
        call output(trim(directory_snap)//'/Srad.dat',Srad,1)
      endif

    endsubroutine source_function
!***********************************************************************
    subroutine opacity(f)
!
!  calculates opacity
!
!  03-apr-04/tobi: coded
!
      use Cdata, only: ilnrho,x,y,z,m,n,Lx,Ly,Lz,pi,dx,dy,dz,pi,directory_snap
      use EquationOfState, only: eoscalc
      use Mpicomm, only: stop_it
      use IO, only: output

      real, dimension(mx,my,mz,mvar+maux), intent(in) :: f
      real, dimension(mx) :: tmp,lnrho
      logical, save :: lfirst=.true.

      select case (opacity_type)

      case ('Hminus')
        do m=1,my
        do n=1,mz
          call eoscalc(f,mx,lnchi=tmp)
          lnchi(:,m,n)=tmp
        enddo
        enddo

      case ('kappa_cst')
        do m=1,my
        do n=1,mz
          call eoscalc(f,mx,lnrho=lnrho)
          lnchi(:,m,n)=log(kappa_cst)+lnrho
        enddo
        enddo

      case ('blob')
        if (lfirst) then
          lnchi=lnchi_const &
               +ampllnchi*spread(spread(exp(-(x/radius_lnchi)**2),2,my),3,mz) &
                         *spread(spread(exp(-(y/radius_lnchi)**2),1,mx),3,mz) &
                         *spread(spread(exp(-(z/radius_lnchi)**2),1,mx),2,my)
          lfirst=.false.
        endif

      case ('cos')
        if (lfirst) then
          lnchi=lnchi_const &
               +ampllnchi*spread(spread(cos(kx_lnchi*x),2,my),3,mz) &
                         *spread(spread(cos(ky_lnchi*y),1,mx),3,mz) &
                         *spread(spread(cos(kz_lnchi*z),1,mx),2,my)
          lfirst=.false.
        endif


      case default
        call stop_it('no such opacity type: '//trim(opacity_type))

      endselect

      if (lrad_debug) then
        call output(trim(directory_snap)//'/lnchi.dat',lnchi,1)
      endif

    endsubroutine opacity
!***********************************************************************
    subroutine init_rad(f,xx,yy,zz)
!
!  Dummy routine for Flux Limited Diffusion routine
!  initialise radiation; called from start.f90
!
!  15-jul-2002/nils: dummy routine
!
      use Cdata
      use Sub
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz)      :: xx,yy,zz
!
      if(NO_WARN) print*,f,xx,yy,zz !(keep compiler quiet)
    endsubroutine init_rad
!***********************************************************************
    subroutine pencil_criteria_radiation()
! 
!  All pencils that the Radiation module depends on are specified here.
! 
!  21-11-04/anders: coded
!
      if (lcooling) then
        lpenc_requested(i_TT1)=.true.
        lpenc_requested(i_lnrho)=.true.
      endif
!
    endsubroutine pencil_criteria_radiation
!***********************************************************************
    subroutine pencil_interdep_radiation(lpencil_in)
!
!  Interdependency among pencils provided by the Radiation module
!  is specified here.
!
!  21-11-04/anders: coded
! 
      logical, dimension (npencils) :: lpencil_in
! 
      if (NO_WARN) print*, lpencil_in  !(keep compiler quiet)
! 
    endsubroutine pencil_interdep_radiation
!***********************************************************************
    subroutine calc_pencils_radiation(f,p)
!   
!  Calculate Radiation pencils.
!  Most basic pencils should come first, as others may depend on them.
! 
!  21-11-04/anders: coded
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      type (pencil_case) :: p
!      
      intent(in) :: f,p
! 
      if (NO_WARN) print*, f !(keep compiler quiet)
! 
    endsubroutine calc_pencils_radiation
!***********************************************************************
   subroutine de_dt(f,df,p,gamma)
!
!  Dummy routine for Flux Limited Diffusion routine
!
!  15-jul-2002/nils: dummy routine
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,mvar) :: df
      type (pencil_case) :: p
      real :: gamma
!
      if(NO_WARN) print*,f,df,p,gamma !(keep compiler quiet)
!        
    endsubroutine de_dt
!***********************************************************************
    subroutine read_radiation_init_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat

      if (present(iostat)) then
        read(unit,NML=radiation_init_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=radiation_init_pars,ERR=99)
      endif


99    return
    endsubroutine read_radiation_init_pars
!***********************************************************************
    subroutine write_radiation_init_pars(unit)
      integer, intent(in) :: unit

      write(unit,NML=radiation_init_pars)

    endsubroutine write_radiation_init_pars
!***********************************************************************
    subroutine read_radiation_run_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat

      if (present(iostat)) then
        read(unit,NML=radiation_run_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=radiation_run_pars,ERR=99)
      endif


99    return
    endsubroutine read_radiation_run_pars
!***********************************************************************
    subroutine write_radiation_run_pars(unit)
      integer, intent(in) :: unit

      write(unit,NML=radiation_run_pars)

    endsubroutine write_radiation_run_pars
!*******************************************************************
    subroutine rprint_radiation(lreset,lwrite)
!
!  Dummy routine for Flux Limited Diffusion routine
!  reads and registers print parameters relevant for radiative part
!
!  16-jul-02/nils: adapted from rprint_hydro
!
      use Cdata
      use Sub
!  
      integer :: iname
      logical :: lreset,lwr
      logical, optional :: lwrite
!
      lwr = .false.
      if (present(lwrite)) lwr=lwrite
!
!  reset everything in case of RELOAD
!  (this needs to be consistent with what is defined above!)
!
      if (lreset) then
        idiag_Qradrms=0; idiag_Qradmax=0
      endif
!
!  check for those quantities that we want to evaluate online
!
      do iname=1,nname
        call parse_name(iname,cname(iname),cform(iname),'Qradrms',idiag_Qradrms)
        call parse_name(iname,cname(iname),cform(iname),'Qradmax',idiag_Qradmax)
      enddo
!
!  write column where which radiative variable is stored
!
      if (lwr) then
        write(3,*) 'i_frms=',idiag_frms
        write(3,*) 'i_fmax=',idiag_fmax
        write(3,*) 'i_Erad_rms=',idiag_Erad_rms
        write(3,*) 'i_Erad_max=',idiag_Erad_max
        write(3,*) 'i_Egas_rms=',idiag_Egas_rms
        write(3,*) 'i_Egas_max=',idiag_Egas_max
        write(3,*) 'i_Qradrms=',idiag_Qradrms
        write(3,*) 'i_Qradmax=',idiag_Qradmax
        write(3,*) 'nname=',nname
        write(3,*) 'ie=',ie
        write(3,*) 'ifx=',ifx
        write(3,*) 'ify=',ify
        write(3,*) 'ifz=',ifz
        write(3,*) 'iQrad=',iQrad
      endif
!   
      if(NO_WARN) print*,lreset  !(to keep compiler quiet)
    endsubroutine rprint_radiation
!***********************************************************************
    subroutine  bc_ee_inflow_x(f,topbot)
!
!  Dummy routine for Flux Limited Diffusion routine
!
!  8-aug-02/nils: coded
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mvar+maux) :: f
!
      if (ip==1) print*,topbot,f(1,1,1,1)  !(to keep compiler quiet)
!
    end subroutine bc_ee_inflow_x
!***********************************************************************
    subroutine  bc_ee_outflow_x(f,topbot)
!
!  Dummy routine for Flux Limited Diffusion routine
!
!  8-aug-02/nils: coded
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mvar+maux) :: f
!
      if (ip==1) print*,topbot,f(1,1,1,1)  !(to keep compiler quiet)
!
    end subroutine bc_ee_outflow_x
!***********************************************************************

endmodule Radiation
