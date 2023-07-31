#![no_std]
#![no_main]

extern crate alloc;

use alloc::string::ToString;
use raw_cpuid::{CpuId, CpuIdReaderNative};
use spin::Once;
use uefi::proto::console::text::{Color, Input, Key, ScanCode};
use uefi::{prelude::*, table::runtime::ResetType, Error};

static CPUID: Once<CpuId<CpuIdReaderNative>> = Once::new();

fn getkey(bs: &BootServices, input: &mut Input) -> Result<Key, Error<Option<usize>>> {
    let mut events = unsafe { [input.wait_for_key_event().unsafe_clone()] };

    let keypress = loop {
        bs.wait_for_event(&mut events)?;
        if let Some(key) = input
            .read_key()
            .map_err(|err| Error::new(err.status(), None))?
        {
            break key;
        }
    };

    Ok(keypress)
}

unsafe fn boot_main_setup(_ihandle: Handle, mut systab: SystemTable<Boot>) -> uefi::Result<()> {
    // SETUP: setup screen "stdout"
    systab
        .stdout()
        .set_color(Color::Cyan, Color::Black)
        .and_then(|_| systab.stdout().reset(true))
        .and_then(|_| systab.stdout().enable_cursor(true))?;

    log::info!(
        "EFI Vendor: {vendor}, revision: {revision}",
        vendor = systab.firmware_vendor(),
        revision = systab.uefi_revision()
    );

    log::info!(
        "CPU Vendor: {}",
        unsafe { CPUID.get_unchecked() }
            .get_vendor_info()
            .map_or("Unknown".into(), |vinfo| vinfo.as_str().to_string())
    );

    uefi_services::print!("\n\nPress Esc to quit boot services stage");
    let (_, row) = systab.stdout().cursor_position();
    systab.stdout().set_cursor_position(0, row + 1).unwrap();

    loop {
        match getkey(systab.boot_services(), systab.unsafe_clone().stdin()) {
            Ok(Key::Special(ScanCode::ESCAPE)) => break,
            Ok(_) => continue,
            Err(e) => log::error!("Failed reading from stdin: {}", e.status()),
        }
    }

    log::info!("Quitting boot services stage in 1sec...");
    systab.boot_services().stall(1000000);

    Ok(())
}

#[entry]
fn efi_main(ihandle: Handle, mut systab: SystemTable<Boot>) -> Status {
    CPUID.call_once(CpuId::new);
    uefi_services::init(&mut systab).unwrap();

    // TODO: implement acpi initialization
    // TODO: implement memory initialization
    // TODO: Implement basic interrupt controller for later stage
    // TODO: Implement graphics

    if let Err(e) = unsafe { boot_main_setup(ihandle, systab.unsafe_clone()) } {
        systab
            .runtime_services()
            .reset(ResetType::COLD, e.status(), None);
    }

    let (rttab, _mmap) = systab.exit_boot_services();

    // TODO: how do you load the kernel and switch to it from here?

    unsafe { rttab.runtime_services() }.reset(ResetType::SHUTDOWN, Status::SUCCESS, None)
}
